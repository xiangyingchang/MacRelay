import Foundation
import Network

/// Local relay WebSocket server for iPhone handoff.
///
/// The transport is a real WebSocket listener built on Network.framework; the
/// command semantics stay isolated in `handleMessage(_:)` so probes and future
/// transports can reuse the same snapshot/replay/heartbeat dispatch path.
public final class MacRelayWebSocketServer {
    private let relayService: MacRelayService
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var readySemaphore: DispatchSemaphore?
    private var failedStartError: NWError?

    public init(relayService: MacRelayService, queue: DispatchQueue = DispatchQueue(label: "MacRelayWebSocketServer")) {
        self.relayService = relayService
        self.queue = queue
    }

    public var port: UInt16? {
        listener?.port?.rawValue
    }

    public func start(host: String = "127.0.0.1", port: UInt16 = 0) throws {
        if listener != nil {
            stop()
        }

        let webSocketOptions = NWProtocolWebSocket.Options()
        webSocketOptions.autoReplyPing = true

        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: nwPort)

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.readySemaphore?.signal()
            case .failed(let error):
                self?.failedStartError = error
                self?.readySemaphore?.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func waitUntilReady(timeout seconds: TimeInterval = 5) -> Bool {
        if let port, port != 0 { return true }
        let semaphore = DispatchSemaphore(value: 0)
        readySemaphore = semaphore
        let result = semaphore.wait(timeout: .now() + seconds)
        readySemaphore = nil
        return result == .success && failedStartError == nil && (port ?? 0) != 0
    }

    public func stop() {
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        failedStartError = nil
        readySemaphore = nil
    }

    private func handle(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.receive(on: connection)
            case .cancelled, .failed:
                self.connections.removeAll { $0 === connection }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            self?.handleReceivedMessage(data: data, context: context, error: error, connection: connection)
        }
    }

    private func handleReceivedMessage(
        data: Data?,
        context: NWConnection.ContentContext?,
        error: NWError?,
        connection: NWConnection
    ) {
        if error != nil {
            connection.cancel()
            return
        }

        if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
            switch metadata.opcode {
            case .text, .binary:
                if let data, !data.isEmpty {
                    send(handleMessage(data), on: connection)
                }
            case .close:
                connection.cancel()
                return
            default:
                break
            }
        } else if let data, !data.isEmpty {
            // Defensive fallback for tests or future transports that call into
            // this connection path without WebSocket metadata.
            send(handleMessage(data), on: connection)
        }

        receive(on: connection)
    }

    public func handleMessage(_ data: Data) -> Data {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Relay envelope must be an object with type"))
            }
            let id = object["id"] as? String
            let payloadData: Data? = try object["payload"].map { payload in
                try JSONSerialization.data(withJSONObject: payload, options: [])
            }
            switch type {
            case RelayCommandType.snapshotGet.rawValue:
                return try encode(relayService.snapshotEnvelope(correlationID: id))
            case RelayCommandType.replayFrom.rawValue:
                let replayRequest = try payloadData.map {
                    try JSONDecoder().decode(RelayReplayRequestPayload.self, from: $0)
                } ?? RelayReplayRequestPayload(afterSeq: 0)
                let payload = RelayHTTPReplayPayload(result: relayService.replay(afterSeq: replayRequest.afterSeq, maxEvents: replayRequest.maxEvents))
                return try encode(RelayEnvelope(type: RelayCommandType.replayFrom.rawValue, correlationID: id, payload: payload))
            case RelayCommandType.heartbeatPing.rawValue:
                let connection = ConnectionSnapshotPayload(isPaired: true, isOnline: true, lastSeenSeq: relayService.newestSeq)
                return try encode(RelayEnvelope(type: RelayEventType.heartbeat.rawValue, correlationID: id, payload: connection))
            default:
                return try encode(RelayEnvelope(type: RelayEventType.error.rawValue, correlationID: id, payload: ["error": "unsupported command"] as [String: String]))
            }
        } catch {
            return (try? encode(RelayEnvelope(type: RelayEventType.error.rawValue, payload: ["error": "\(error)"] as [String: String]))) ?? Data()
        }
    }

    private func encode<Payload: Encodable>(_ envelope: RelayEnvelope<Payload>) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    private func send(_ data: Data, on connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "mac-relay-json", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
            if error != nil {
                connection.cancel()
            }
        })
    }
}
