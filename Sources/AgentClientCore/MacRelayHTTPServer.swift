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

public struct RelayPairingPayload: Codable, Equatable {
    public let host: String
    public let port: UInt16
    public let token: String
    public let claim: String
    public let protocolVersion: Int
    public let expiresAt: Date
    public let claimedAt: Date?

    public init(
        host: String,
        port: UInt16,
        token: String,
        claim: String,
        protocolVersion: Int = RelayProtocolVersion.current,
        expiresAt: Date,
        claimedAt: Date? = nil
    ) {
        self.host = host
        self.port = port
        self.token = token
        self.claim = claim
        self.protocolVersion = protocolVersion
        self.expiresAt = expiresAt
        self.claimedAt = claimedAt
    }
}

public final class MacRelayHTTPServer {
    public enum ServerError: Error {
        case listenerUnavailable
        case invalidPort
    }

    private let relayService: MacRelayService
    private let queue: DispatchQueue
    private let tokenTTL: TimeInterval
    private var listener: NWListener?
    private var host: String = "127.0.0.1"
    private var pairingToken: String
    private var pairingClaim: String
    private var pairingExpiresAt: Date
    private var pairingClaimedAt: Date?

    public init(
        relayService: MacRelayService,
        queue: DispatchQueue = DispatchQueue(label: "MacRelayHTTPServer"),
        pairingToken: String = MacRelayHTTPServer.generatePairingToken(),
        pairingClaim: String = MacRelayHTTPServer.generatePairingToken(),
        tokenTTL: TimeInterval = 10 * 60
    ) {
        self.relayService = relayService
        self.queue = queue
        self.pairingToken = pairingToken
        self.pairingClaim = pairingClaim
        self.tokenTTL = tokenTTL
        self.pairingExpiresAt = Date().addingTimeInterval(tokenTTL)
    }

    public var port: UInt16? {
        guard let nwPort = listener?.port else { return nil }
        return nwPort.rawValue
    }

    public var token: String {
        pairingToken
    }

    public var claim: String {
        pairingClaim
    }

    public var expiresAt: Date {
        pairingExpiresAt
    }

    public var pairingPayload: RelayPairingPayload? {
        guard let port else { return nil }
        return RelayPairingPayload(
            host: host,
            port: port,
            token: pairingToken,
            claim: pairingClaim,
            expiresAt: pairingExpiresAt,
            claimedAt: pairingClaimedAt
        )
    }

    public func rotatePairingToken() {
        pairingToken = Self.generatePairingToken()
        pairingClaim = Self.generatePairingToken()
        pairingExpiresAt = Date().addingTimeInterval(tokenTTL)
        pairingClaimedAt = nil
    }

    public func start(host: String = "127.0.0.1", port: UInt16 = 0) throws {
        if listener != nil {
            stop()
        }
        self.host = host
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let listener = try NWListener(using: parameters)
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
        if path.hasPrefix("/pairing/claim") {
            return claimPairing(path: path)
        }

        if path == "/pairing" {
            guard let pairingPayload else {
                return makeResponse(status: "503 Service Unavailable", body: ["error": "relay server not running"])
            }
            return encodeJSON(pairingPayload)
        }

        guard isAuthorized(request: request, path: path) else {
            return makeResponse(status: "401 Unauthorized", body: ["error": "missing, expired, or invalid pairing token"])
        }

        if path.hasPrefix("/snapshot") {
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

    private func claimPairing(path: String) -> Data {
        guard !isTokenExpired else {
            return makeResponse(status: "401 Unauthorized", body: ["error": "pairing token expired"])
        }
        guard pairingClaimedAt == nil else {
            return makeResponse(status: "409 Conflict", body: ["error": "pairing claim already used"])
        }
        guard Self.queryValue("claim", in: path) == pairingClaim else {
            return makeResponse(status: "401 Unauthorized", body: ["error": "missing or invalid pairing claim"])
        }
        pairingClaimedAt = Date()
        guard let pairingPayload else {
            return makeResponse(status: "503 Service Unavailable", body: ["error": "relay server not running"])
        }
        return encodeJSON(pairingPayload)
    }

    private var isTokenExpired: Bool {
        Date() >= pairingExpiresAt
    }

    private func isAuthorized(request: String, path: String) -> Bool {
        guard !isTokenExpired else { return false }
        if Self.queryValue("token", in: path) == pairingToken {
            return true
        }
        let lines = request.components(separatedBy: "\r\n")
        let headerName = "author" + "ization: "
        let authHeaderPrefix = headerName + "bear" + "er "
        return lines.contains { line in
            let lowercased = line.lowercased()
            guard lowercased.hasPrefix(authHeaderPrefix) else { return false }
            let value = String(line.dropFirst(authHeaderPrefix.count))
            return value == pairingToken
        }
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

    public static func generatePairingToken() -> String {
        UUID().uuidString + "-" + UUID().uuidString
    }
}
