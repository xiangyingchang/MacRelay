import Foundation
import Network

/// First relay message server for the HTTP → WebSocket transition.
///
/// It uses the same JSON envelope that the final WebSocket transport will use,
/// and runs over a local TCP listener for this M1 probe slice. The transport can
/// be swapped to a true WebSocket handshake without changing command handling.
public final class MacRelayWebSocketServer {
    private struct IncomingEnvelope: Decodable {
        let id: String?
        let type: String
        let payload: Data?

        enum CodingKeys: String, CodingKey {
            case id
            case type
            case payload
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            type = try container.decode(String.self, forKey: .type)
            if container.contains(.payload) {
                payload = try container.decode(RawJSON.self, forKey: .payload).data
            } else {
                payload = nil
            }
        }
    }

    private struct RawJSON: Decodable {
        let data: Data

        init(from decoder: Decoder) throws {
            let object = try Self.decodeObject(from: decoder)
            data = try JSONSerialization.data(withJSONObject: object, options: [])
        }

        private static func decodeObject(from decoder: Decoder) throws -> Any {
            if let container = try? decoder.singleValueContainer() {
                if container.decodeNil() { return NSNull() }
                if let value = try? container.decode(Bool.self) { return value }
                if let value = try? container.decode(Int.self) { return value }
                if let value = try? container.decode(Double.self) { return value }
                if let value = try? container.decode(String.self) { return value }
            }
            if var array = try? decoder.unkeyedContainer() {
                var values: [Any] = []
                while !array.isAtEnd {
                    values.append(try array.decode(RawJSON.self).jsonObject())
                }
                return values
            }
            let keyed = try decoder.container(keyedBy: DynamicCodingKey.self)
            var object: [String: Any] = [:]
            for key in keyed.allKeys {
                object[key.stringValue] = try keyed.decode(RawJSON.self, forKey: key).jsonObject()
            }
            return object
        }

        private func jsonObject() throws -> Any {
            try JSONSerialization.jsonObject(with: data)
        }
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    private let relayService: MacRelayService
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var connections: [NWConnection] = []

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
        let parameters = NWParameters.tcp
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            self?.handleReceived(data: data, isComplete: isComplete, error: error, connection: connection)
        }
    }

    private func handleReceived(data: Data?, isComplete: Bool, error: NWError?, connection: NWConnection) {
        if error != nil || isComplete {
            connection.cancel()
            return
        }
        if let data, !data.isEmpty {
            let response = handleMessage(trimLine(data))
            send(response, on: connection)
        }
        receive(on: connection)
    }

    private func trimLine(_ data: Data) -> Data {
        let newline = UInt8(ascii: "\n")
        guard let index = data.firstIndex(of: newline) else { return data }
        return Data(data[..<index])
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
        var data = try encoder.encode(envelope)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { error in
            if error != nil {
                connection.cancel()
            }
        })
    }
}
