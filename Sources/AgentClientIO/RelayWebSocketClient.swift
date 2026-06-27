import AgentClientCore
import Foundation

/// Reusable iOS-compatible WebSocket client for MacRelay.
///
/// Handles connection lifecycle, auth (token + challenge-response),
/// and command/response correlation over a single WebSocket connection.
@MainActor
public final class RelayWebSocketClient {
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var host: String = ""
    private var port: UInt16 = 0
    private var pendingResponses: [String: CheckedContinuation<Data, Error>] = [:]
    private var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    public var onSnapshot: ((RelayEnvelope<RelaySnapshotPayload>) -> Void)?
    public var onConnectionLost: ((Error) -> Void)?

    public var isConnected: Bool { task != nil }

    public init() {}

    // MARK: - Connection

    public func connect(host: String, port: UInt16) {
        self.host = host
        self.port = port
        let session = URLSession(configuration: .ephemeral)
        let t = session.webSocketTask(with: URL(string: "ws://\(host):\(port)/relay")!)
        t.resume()
        self.task = t
    }

    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        let error = RelayClientError.wsError("disconnected")
        pendingResponses.values.forEach { $0.resume(throwing: error) }
        pendingResponses.removeAll()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    // MARK: - Auth

    /// Authenticate with a pairing token.
    public func authenticate(token: String) async throws {
        let authEnv = RelayEnvelope(type: "mac-relay.authorize", payload: ["token": token] as [String: String])
        let result: RelayEnvelope<[String: String]> = try await sendAndDecodeDirect(authEnv)
        guard result.type == "mac-relay.authenticated" else {
            throw RelayClientError.authFailed(result.payload["error"] ?? "unknown")
        }
        startReceiveLoop()
    }

    /// Authenticate with device credential via challenge-response.
    public func authenticate(deviceID: String, deviceSecret: String) async throws {
        // Step 1: request challenge
        let reqEnv = RelayEnvelope(type: "mac-relay.authorize", payload: ["deviceId": deviceID] as [String: String])
        let challengeResult: RelayEnvelope<[String: String]> = try await sendAndDecodeDirect(reqEnv)

        guard challengeResult.type == "mac-relay.challenge",
              let nonce = challengeResult.payload["nonce"] else {
            throw RelayClientError.challengeFailed("no challenge received")
        }

        // Step 2: sign and send response
        let response = NonceManager.hash(nonce, withSecret: deviceSecret)
        let authEnv = RelayEnvelope(type: "mac-relay.authorize", payload: [
            "deviceId": deviceID,
            "challengeResponse": response
        ] as [String: String])

        let authResult: RelayEnvelope<[String: String]> = try await sendAndDecodeDirect(authEnv)
        guard authResult.type == "mac-relay.authenticated" else {
            throw RelayClientError.authFailed(authResult.payload["error"] ?? "unknown")
        }
        startReceiveLoop()
    }

    // MARK: - Commands

    public func getSnapshot() async throws -> RelayEnvelope<RelaySnapshotPayload> {
        let cmd = RelayEnvelope(type: RelayCommandType.snapshotGet.rawValue, payload: [:] as [String: String])
        return try await sendAndDecode(cmd)
    }

    public func getReplay(afterSeq: UInt64, maxEvents: Int? = nil) async throws -> RelayEnvelope<RelayHTTPReplayPayload> {
        let payload = RelayReplayRequestPayload(afterSeq: afterSeq, maxEvents: maxEvents)
        let cmd = RelayEnvelope(type: RelayCommandType.replayFrom.rawValue, payload: payload)
        return try await sendAndDecode(cmd)
    }

    public func heartbeat() async throws -> RelayEnvelope<ConnectionSnapshotPayload> {
        let cmd = RelayEnvelope(type: RelayCommandType.heartbeatPing.rawValue, payload: [:] as [String: String])
        return try await sendAndDecode(cmd)
    }

    /// Send a generic relay command with typed payload and decode the response.
    public func sendCommand<Payload: Codable, Response: Decodable>(
        type: RelayCommandType,
        payload: Payload
    ) async throws -> RelayEnvelope<Response> {
        let cmd = RelayEnvelope(type: type.rawValue, payload: payload)
        return try await sendAndDecode(cmd)
    }

    // MARK: - Internal

    private func sendAndDecodeDirect<T: Decodable>(_ envelope: some Encodable) async throws -> T {
        guard let task else { throw RelayClientError.wsError("not connected") }
        let text = try encodeText(envelope)
        try await task.send(.string(text))
        let responseData = try await receiveData(from: task)
        return try decoder.decode(T.self, from: responseData)
    }

    private func sendAndDecode<T: Decodable>(_ envelope: RelayEnvelope<some Encodable>) async throws -> T {
        guard let task else { throw RelayClientError.wsError("not connected") }
        let text = try encodeText(envelope)
        let responseData = try await withCheckedThrowingContinuation { continuation in
            pendingResponses[envelope.id] = continuation
            Task {
                do {
                    try await task.send(.string(text))
                } catch {
                    await MainActor.run {
                        self.pendingResponses.removeValue(forKey: envelope.id)?.resume(throwing: error)
                    }
                }
            }
        }
        return try decoder.decode(T.self, from: responseData)
    }

    private func encodeText(_ envelope: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    guard let task = self.task else { return }
                    let data = try await self.receiveData(from: task)
                    self.routeIncoming(data)
                } catch {
                    self.failPendingResponses(error)
                    self.task = nil
                    self.onConnectionLost?(error)
                    return
                }
            }
        }
    }

    private func receiveData(from task: URLSessionWebSocketTask) async throws -> Data {
        let message = try await task.receive()
        let responseData: Data = switch message {
        case .data(let d): d
        case .string(let s): Data(s.utf8)
        @unknown default: throw RelayClientError.wsError("unknown frame")
        }
        return responseData
    }

    private func routeIncoming(_ data: Data) {
        guard let metadata = try? decoder.decode(RelayIncomingMetadata.self, from: data) else {
            return
        }
        if let correlationID = metadata.correlationID,
           let continuation = pendingResponses.removeValue(forKey: correlationID) {
            continuation.resume(returning: data)
            return
        }
        if metadata.type == RelayEventType.snapshot.rawValue,
           let snapshot = try? decoder.decode(RelayEnvelope<RelaySnapshotPayload>.self, from: data) {
            onSnapshot?(snapshot)
        }
    }

    private func failPendingResponses(_ error: Error) {
        pendingResponses.values.forEach { $0.resume(throwing: error) }
        pendingResponses.removeAll()
    }
}

private struct RelayIncomingMetadata: Decodable {
    var type: String
    var correlationID: String?
}
