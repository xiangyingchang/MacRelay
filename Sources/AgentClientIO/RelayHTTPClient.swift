import AgentClientCore
import Foundation

public struct RelayHTTPClient {
    public let baseURL: URL

    public init(host: String, port: UInt16) {
        self.baseURL = URL(string: "http://\(host):\(port)")!
    }

    public func getPairing() async throws -> RelayPairingPayload {
        let data = try await get(path: "/pairing")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RelayPairingPayload.self, from: data)
    }

    public func claimPairing(claim: String) async throws -> RelayPairingPayload {
        let data = try await get(path: "/pairing/claim?claim=\(claim)")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RelayPairingPayload.self, from: data)
    }

    public func getSnapshot(token: String) async throws -> RelayEnvelope<RelaySnapshotPayload> {
        let data = try await get(path: "/snapshot?token=\(token)")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RelayEnvelope<RelaySnapshotPayload>.self, from: data)
    }

    public func getReplay(afterSeq: UInt64, maxEvents: Int?, token: String) async throws -> RelayHTTPReplayPayload {
        var path = "/replay?afterSeq=\(afterSeq)&token=\(token)"
        if let max = maxEvents { path += "&maxEvents=\(max)" }
        let data = try await get(path: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RelayHTTPReplayPayload.self, from: data)
    }

    private func get(path: String) async throws -> Data {
        let url = URL(string: path, relativeTo: baseURL) ?? baseURL
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RelayClientError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }
}

public enum RelayClientError: Error, CustomStringConvertible, LocalizedError {
    case httpError(status: Int)
    case wsError(String)
    case authFailed(String)
    case challengeFailed(String)
    case invalidPairingInput

    public var description: String {
        switch self {
        case .httpError(let s): return "HTTP \(s)"
        case .wsError: return "WebSocket error"
        case .authFailed: return "Auth failed"
        case .challengeFailed: return "Challenge failed"
        case .invalidPairingInput: return "Invalid pairing URI or payload"
        }
    }

    public var errorDescription: String? { description }

    /// Error code suitable for UI display (safe, no context leak).
    public var code: String {
        switch self {
        case .httpError: return RelayErrorCode.generalError.code
        case .wsError: return RelayErrorCode.generalError.code
        case .authFailed: return RelayErrorCode.authInvalid.code
        case .challengeFailed: return RelayErrorCode.authInvalid.code
        case .invalidPairingInput: return RelayErrorCode.generalError.code
        }
    }
}
