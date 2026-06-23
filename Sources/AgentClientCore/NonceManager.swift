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
/// Uses pluggable `RelayChallengeSigner` for the cryptographic hash.
public final class NonceManager {
    private var pendingChallenges: [String: RelayChallengePayload] = [:];
    private var usedNonces: Set<String> = []
    private let maxUsed = 1000
    public let signer: RelayChallengeSigner

    public init(signer: RelayChallengeSigner = SHA256Signer()) {
        self.signer = signer
    }

    public func issueNonce(deviceID: String) -> RelayChallengePayload {
        let challenge = RelayChallengePayload(deviceID: deviceID)
        pendingChallenges[deviceID] = challenge
        return challenge
    }

    public func verify(deviceID: String, secret: String, challengeResponse: String) -> Bool {
        guard let challenge = pendingChallenges[deviceID] else { return false }
        guard !usedNonces.contains(challenge.nonce) else { return false }

        let expected = signer.sign(challenge: challenge.nonce, secret: secret)
        let ok = expected == challengeResponse
        if ok {
            pendingChallenges.removeValue(forKey: deviceID)
            usedNonces.insert(challenge.nonce)
            if usedNonces.count > maxUsed { usedNonces.removeFirst() }
        }
        return ok
    }

    public func revokeChallenge(deviceID: String) {
        pendingChallenges.removeValue(forKey: deviceID)
    }

    /// Legacy static convenience — delegates to SHA256Signer.
    public static func hash(_ nonce: String, withSecret secret: String) -> String {
        SHA256Signer().sign(challenge: nonce, secret: secret)
    }
}
