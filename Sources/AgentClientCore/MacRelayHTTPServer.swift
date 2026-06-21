import Foundation
import Network

public struct RelayHTTPReplayPayload: Codable {
    public var kind: String
    public var reason: String?
    public var events: [StoredRelayEvent]

    public init(result: EventReplayResult) {
        switch result {
        case let .events(events):
            self.kind = "events"
            self.reason = nil
            self.events = events
        case let .needsFullSnapshot(reason):
            self.kind = "needsFullSnapshot"
            self.reason = reason
            self.events = []
        }
    }
}

public final class MacRelayHTTPServer {
    public enum ServerError: Error {
        case listenerUnavailable
        case invalidPort
    }

    private let relayService: MacRelayService
    private let queue: DispatchQueue
    private var listener: NWListener?

    public init(relayService: MacRelayService, queue: DispatchQueue = DispatchQueue(label: "MacRelayHTTPServer")) {
        self.relayService = relayService
        self.queue = queue
    }

    public var port: UInt16? {
        guard let nwPort = listener?.port else { return nil }
        return nwPort.rawValue
    }

    public func start(host: NWEndpoint.Host = "127.0.0.1", port: UInt16 = 0) throws {
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
        let listener = try NWListener(using: .tcp, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let response = self.response(for: request)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(for request: String) -> Data {
        let line = request.components(separatedBy: "\r\n").first ?? ""
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else {
            return makeResponse(status: "400 Bad Request", body: ["error": "invalid request line"])
        }

        let path = String(parts[1])
        if path == "/snapshot" {
            return encodeJSON(relayService.snapshotEnvelope())
        }

        if path.hasPrefix("/replay") {
            let afterSeq = Self.queryValue("afterSeq", in: path).flatMap(UInt64.init) ?? 0
            let maxEvents = Self.queryValue("maxEvents", in: path).flatMap(Int.init)
            let payload = RelayHTTPReplayPayload(result: relayService.replay(afterSeq: afterSeq, maxEvents: maxEvents))
            return encodeJSON(payload)
        }

        return makeResponse(status: "404 Not Found", body: ["error": "not found"])
    }

    private func encodeJSON<Payload: Encodable>(_ payload: Payload) -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            return makeResponse(status: "200 OK", bodyData: data)
        } catch {
            return makeResponse(status: "500 Internal Server Error", body: ["error": "\(error)"])
        }
    }

    private func makeResponse(status: String, body: [String: String]) -> Data {
        let data = (try? JSONEncoder().encode(body)) ?? Data("{}".utf8)
        return makeResponse(status: status, bodyData: data)
    }

    private func makeResponse(status: String, bodyData: Data) -> Data {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(bodyData.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(bodyData)
        return data
    }

    private static func queryValue(_ key: String, in path: String) -> String? {
        guard let query = path.split(separator: "?", maxSplits: 1).dropFirst().first else { return nil }
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.first == key {
                return parts.dropFirst().first
            }
        }
        return nil
    }
}
