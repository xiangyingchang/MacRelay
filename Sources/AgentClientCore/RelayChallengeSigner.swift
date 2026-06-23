import Foundation
import CommonCrypto

// MARK: - Signer Protocol

public protocol RelayChallengeSigner {
    func sign(challenge: String, secret: String) -> String
    var algorithm: String { get }
}

// MARK: - SHA256 (current default)

public struct SHA256Signer: RelayChallengeSigner {
    public let algorithm = "SHA256"
    public init() {}

    public func sign(challenge: String, secret: String) -> String {
        let input = challenge + secret
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_SHA256(buf.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - HMAC-SHA256

public struct HMACSHA256Signer: RelayChallengeSigner {
    public let algorithm = "HMAC-SHA256"
    public init() {}

    public func sign(challenge: String, secret: String) -> String {
        let cBytes = Data(challenge.utf8)
        let sBytes = Data(secret.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        cBytes.withUnsafeBytes { cBuf in
            sBytes.withUnsafeBytes { sBuf in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       sBuf.baseAddress, sBytes.count,
                       cBuf.baseAddress, cBytes.count,
                       &digest)
            }
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
