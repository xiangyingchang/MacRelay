import Foundation

/// Short pairing URI that carries the minimum info needed for
/// an iPhone to complete the claim flow without exposing the
/// full token/secret in the QR code.
///
/// Format: `macrelay://pair?host=127.0.0.1&port=48731&claim=<claim>`
public struct RelayPairingURI: Codable, Equatable {
    public let host: String
    public let port: UInt16
    public let claim: String

    public init(host: String, port: UInt16, claim: String) {
        self.host = host; self.port = port; self.claim = claim
    }

    public init?(from uriString: String) {
        guard let comps = URLComponents(string: uriString),
              comps.scheme == "macrelay",
              comps.host == "pair" else { return nil }
        let items = comps.queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]
        guard let host = items["host"], let portStr = items["port"], let port = UInt16(portStr),
              let claim = items["claim"] else { return nil }
        self.init(host: host, port: port, claim: claim)
    }

    /// Initialise from a pairing payload — deliberately excludes token/secret.
    public init(payload: RelayPairingPayload) {
        self.init(host: payload.host, port: payload.port, claim: payload.claim)
    }

    public var uriString: String {
        var c = URLComponents()
        c.scheme = "macrelay"
        c.host = "pair"
        c.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: "\(port)"),
            URLQueryItem(name: "claim", value: claim)
        ]
        return c.string ?? ""
    }

    /// Try to parse either a short URI or a legacy JSON payload.
    public static func detect(_ input: String) -> RelayPairingURI? {
        if let uri = RelayPairingURI(from: input) { return uri }
        // Legacy JSON fallback
        guard let data = input.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(RelayPairingPayload.self, from: data) else { return nil }
        return RelayPairingURI(payload: payload)
    }
}
