import Foundation
import CommonCrypto

/// Nonce challenge sent by the relay server after WebSocket connection.
public struct RelayChallengePayload: Codable, Equatable {
    public let nonce: String
    public let deviceID: String

    public init(deviceID: String) {
        self.deviceID = deviceID
        self.nonce = UUID().uuidString
    }
}

/// Holds challenge-response state per connection.
public final class NonceManager {
    private var pendingChallenges: [String: RelayChallengePayload] = [:]
    private var usedNonces: Set<String> = []
    private let maxUsed = 1000

    public init() {}

    public func issueNonce(deviceID: String) -> RelayChallengePayload {
        let challenge = RelayChallengePayload(deviceID: deviceID)
        pendingChallenges[deviceID] = challenge
        return challenge
    }

    public func verify(deviceID: String, secret: String, challengeResponse: String) -> Bool {
        guard let challenge = pendingChallenges[deviceID] else { return false }
        guard !usedNonces.contains(challenge.nonce) else { return false }

        let expected = Self.hash(challenge.nonce, withSecret: secret)
        let ok = expected == challengeResponse
        if ok {
            pendingChallenges.removeValue(forKey: deviceID)
            usedNonces.insert(challenge.nonce)
            if usedNonces.count > maxUsed {
                usedNonces.removeFirst() // crude eviction for first version
            }
        }
        return ok
    }

    public func revokeChallenge(deviceID: String) {
        pendingChallenges.removeValue(forKey: deviceID)
    }

    public static func hash(_ nonce: String, withSecret secret: String) -> String {
        let input = nonce + secret
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_SHA256(buf.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
