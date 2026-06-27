import Foundation
import Network

/// Local relay WebSocket server for iPhone handoff.
///
/// Supports per-connection pairing-token auth. The first message on every
/// connection must be a `mac-relay.authorize` envelope with a valid token.
/// Unauthenticated connections are sent an error and closed.
public final class MacRelayWebSocketServer {
    private let relayService: MacRelayService
    private let pairingToken: String?
    private let deviceTrustStore: DeviceTrustStore?
    private let commandDispatcher: MacRelayRuntimeCommandDispatcher?
    private let nonceManager = NonceManager()
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var connectionAuthenticated: [ObjectIdentifier: Bool] = [:]
    private var readySemaphore: DispatchSemaphore?
    private var failedStartError: NWError?

    /// Broadcast a data blob to all authenticated connections.
    public func broadcast(data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            for (id, authed) in self.connectionAuthenticated where authed {
                guard let conn = self.connections.first(where: { ObjectIdentifier($0) == id }) else { continue }
                self.send(data, on: conn)
            }
        }
    }

    public init(relayService: MacRelayService,
                pairingToken: String? = nil,
                deviceTrustStore: DeviceTrustStore? = nil,
                commandDispatcher: MacRelayRuntimeCommandDispatcher? = nil,
                queue: DispatchQueue = DispatchQueue(label: "MacRelayWebSocketServer")) {
        self.relayService = relayService
        self.pairingToken = pairingToken
        self.deviceTrustStore = deviceTrustStore
        self.commandDispatcher = commandDispatcher
        self.queue = queue
    }

    public var port: UInt16? {
        listener?.port?.rawValue
    }

    public var isAuthEnabled: Bool {
        pairingToken != nil
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
        connectionAuthenticated.removeAll()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        failedStartError = nil
        readySemaphore = nil
    }

    private func handle(_ connection: NWConnection) {
        connections.append(connection)
        connectionAuthenticated[ObjectIdentifier(connection)] = !isAuthEnabled
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.receive(on: connection)
            case .cancelled, .failed:
                self.connectionAuthenticated.removeValue(forKey: ObjectIdentifier(connection))
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
            cancel(connection)
            return
        }

        let textData: Data?
        if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
            switch metadata.opcode {
            case .text, .binary:
                textData = data
            case .close:
                cancel(connection)
                return
            default:
                textData = nil
            }
        } else {
            textData = data
        }

        guard let textData, !textData.isEmpty else {
            receive(on: connection)
            return
        }

        if !(connectionAuthenticated[ObjectIdentifier(connection)] ?? false) {
            let authResponse = handleAuthorize(textData, connection: connection)
            send(authResponse, on: connection)
            receive(on: connection)
            return
        }

        send(handleRelayCommand(textData), on: connection)
        receive(on: connection)
    }

    private func handleAuthorize(_ data: Data, connection: NWConnection) -> Data {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "mac-relay.authorize" else {
                let errorPayload = try encode(RelayEnvelope(
                    type: RelayEventType.error.rawValue,
                    payload: ["error": "first message must be mac-relay.authorize"] as [String: String]
                ))
                cancelAfterSend(errorPayload, connection: connection)
                return errorPayload
            }

            let payload = object["payload"] as? [String: Any] ?? [:]

            // Device credential auth — challenge-response
            if let deviceID = payload["deviceId"] as? String,
               let store = deviceTrustStore {
                // Challenge-response: client sends response to server-issued nonce
                if let challengeResponse = payload["challengeResponse"] as? String {
                    // Find device secret from trust store and verify
                    let device = store.list().first(where: { $0.deviceID == deviceID })
                    if let device, nonceManager.verify(deviceID: deviceID, secret: device.deviceSecret, challengeResponse: challengeResponse) {
                        connectionAuthenticated[ObjectIdentifier(connection)] = true
                        return try encode(RelayEnvelope(
                            type: "mac-relay.authenticated",
                            payload: ["status": "ok", "method": "device-challenge"] as [String: String]
                        ))
                    }
                }

                // Client sent deviceId without challengeResponse — issue challenge
                if payload["challengeResponse"] == nil && payload["deviceSecret"] == nil {
                    let challenge = nonceManager.issueNonce(deviceID: deviceID)
                    return try encode(RelayEnvelope(
                        type: "mac-relay.challenge",
                        payload: ["nonce": challenge.nonce, "deviceId": challenge.deviceID] as [String: String]
                    ))
                }

                // Legacy static secret fallback
                if let deviceSecret = payload["deviceSecret"] as? String,
                   store.isTrusted(deviceID: deviceID, deviceSecret: deviceSecret) {
                    connectionAuthenticated[ObjectIdentifier(connection)] = true
                    return try encode(RelayEnvelope(
                        type: "mac-relay.authenticated",
                        payload: ["status": "ok", "method": "device-static"] as [String: String]
                    ))
                }
            }

            // Fall back to pairing token
            guard let token = pairingToken else {
                let errorPayload = try encode(RelayEnvelope(
                    type: RelayEventType.error.rawValue,
                    payload: ["error": "auth disabled on server"] as [String: String]
                ))
                cancelAfterSend(errorPayload, connection: connection)
                return errorPayload
            }

            let sentToken = payload["token"] as? String ?? ""
            guard sentToken == token else {
                let errorPayload = try encode(RelayEnvelope(
                    type: RelayEventType.error.rawValue,
                    payload: ["error": "invalid pairing token or device credential", "code": RelayErrorCode.authInvalid.code] as [String: String]
                ))
                cancelAfterSend(errorPayload, connection: connection)
                return errorPayload
            }

            connectionAuthenticated[ObjectIdentifier(connection)] = true
            return try encode(RelayEnvelope(
                type: "mac-relay.authenticated",
                payload: ["status": "ok", "method": "token"] as [String: String]
            ))
        } catch {
            return Data()
        }
    }

    /// Exposed for probes: validate auth without connection lifecycle.
    public func handleAuthorize(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "mac-relay.authorize",
              let token = pairingToken,
              let payload = object["payload"] as? [String: Any],
              payload["token"] as? String == token else {
            return nil
        }
        return try? encode(RelayEnvelope(
            type: "mac-relay.authenticated",
            payload: ["status": "ok"] as [String: String]
        ))
    }

    /// Transport-independent relay command dispatch.
    public func handleRelayCommand(_ data: Data) -> Data {
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
                var envelope = relayService.snapshotEnvelope(correlationID: id)
                // Inject available sessions so iOS clients see the session list
                // on initial snapshot.get (not just push broadcasts).
                if let dispatcher = commandDispatcher {
                    let sessions = DispatchQueue.main.sync { dispatcher.listSessions() }
                    if !sessions.isEmpty {
                        envelope.payload.availableSessions = sessions
                    }
                }
                return try encode(envelope)
            case RelayCommandType.replayFrom.rawValue:
                let replayRequest = try payloadData.map {
                    try JSONDecoder().decode(RelayReplayRequestPayload.self, from: $0)
                } ?? RelayReplayRequestPayload(afterSeq: 0)
                let payload = RelayHTTPReplayPayload(result: relayService.replay(afterSeq: replayRequest.afterSeq, maxEvents: replayRequest.maxEvents))
                return try encode(RelayEnvelope(type: RelayCommandType.replayFrom.rawValue, correlationID: id, payload: payload))
            case RelayCommandType.heartbeatPing.rawValue:
                let connection = ConnectionSnapshotPayload(isPaired: true, isOnline: true, lastSeenSeq: relayService.newestSeq)
                return try encode(RelayEnvelope(type: RelayEventType.heartbeat.rawValue, correlationID: id, payload: connection))

            case RelayCommandType.sessionList.rawValue:
                guard let commandDispatcher else {
                    return try encode(RelayEnvelope(type: RelayEventType.error.rawValue, correlationID: id, payload: ["error": "remote commands not supported on this server", "code": RelayErrorCode.commandUnsupported.code] as [String: String]))
                }
                let sessions = DispatchQueue.main.sync { commandDispatcher.listSessions() }
                let payload = RelayEnvelope(type: type, correlationID: id, payload: sessions)
                return try encode(payload)

            case RelayCommandType.turnStart.rawValue, RelayCommandType.sessionStart.rawValue, RelayCommandType.settingsUpdate.rawValue, RelayCommandType.sessionStop.rawValue, RelayCommandType.sessionSelect.rawValue:
                guard let commandDispatcher, let payloadData else {
                    return try encode(RelayEnvelope(type: RelayEventType.error.rawValue, correlationID: id, payload: ["error": "remote commands not supported on this server", "code": RelayErrorCode.commandUnsupported.code] as [String: String]))
                }
                let cmdType: RelayCommandType
                if type == RelayCommandType.settingsUpdate.rawValue {
                    cmdType = .settingsUpdate
                } else if type == RelayCommandType.sessionStart.rawValue {
                    cmdType = .sessionStart
                } else if type == RelayCommandType.sessionStop.rawValue {
                    cmdType = .sessionStop
                } else if type == RelayCommandType.sessionSelect.rawValue {
                    cmdType = .sessionSelect
                } else {
                    cmdType = .turnStart
                }
                let dispatchedText: String
                do {
                    let result = try DispatchQueue.main.sync {
                        try commandDispatcher.dispatch(commandType: cmdType, payloadData: payloadData)
                    }
                    dispatchedText = result.description
                } catch {
                    return try encode(RelayEnvelope(type: RelayEventType.error.rawValue, correlationID: id, payload: ["error": "\(error)", "code": RelayErrorCode.generalError.code] as [String: String]))
                }
                return try encode(RelayEnvelope(type: type, correlationID: id, payload: ["dispatched": dispatchedText] as [String: String]))

            default:
                return try encode(RelayEnvelope(type: RelayEventType.error.rawValue, correlationID: id, payload: ["error": "unsupported command", "code": RelayErrorCode.commandUnsupported.code] as [String: String]))
            }
        } catch {
            print("[MacRelayWS] handleRelayCommand error: \(error)")
            return (try? encode(RelayEnvelope(type: RelayEventType.error.rawValue, payload: ["error": "json processing failed: \(error)", "code": RelayErrorCode.generalError.code] as [String: String]))) ?? Data()
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
                self.cancel(connection)
            }
        })
    }

    private func cancelAfterSend(_ data: Data, connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "mac-relay-json", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in
            self.cancel(connection)
        })
    }

    private func cancel(_ connection: NWConnection) {
        connectionAuthenticated.removeValue(forKey: ObjectIdentifier(connection))
        connections.removeAll { $0 === connection }
        connection.cancel()
    }
}
