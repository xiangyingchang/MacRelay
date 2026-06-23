import AgentClientCore
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let m): return m } }
}

// SHA256Signer
let sha = SHA256Signer()
let r1 = sha.sign(challenge: "nonce1", secret: "sec")
guard !r1.isEmpty else { throw ProbeError.failed("SHA256 empty") }
guard sha.algorithm == "SHA256" else { throw ProbeError.failed("sha algo") }

// HMAC-SHA256
let hmac = HMACSHA256Signer()
let r2 = hmac.sign(challenge: "nonce1", secret: "sec")
guard !r2.isEmpty else { throw ProbeError.failed("HMAC empty") }
guard hmac.algorithm == "HMAC-SHA256" else { throw ProbeError.failed("hmac algo") }
guard r2 != r1 else { throw ProbeError.failed("HMAC should differ from SHA256") }

// NonceManager with pluggable signer
let shaMgr = NonceManager(signer: SHA256Signer())
let challenge = shaMgr.issueNonce(deviceID: "d1")
let shaResp = shaMgr.signer.sign(challenge: challenge.nonce, secret: "sec")
guard shaMgr.verify(deviceID: "d1", secret: "sec", challengeResponse: shaResp) else {
    throw ProbeError.failed("SHA256 verify")
}

let hmacMgr = NonceManager(signer: HMACSHA256Signer())
let ch2 = hmacMgr.issueNonce(deviceID: "d2")
let hmacResp = hmacMgr.signer.sign(challenge: ch2.nonce, secret: "sec")
guard hmacMgr.verify(deviceID: "d2", secret: "sec", challengeResponse: hmacResp) else {
    throw ProbeError.failed("HMAC verify")
}

// Wrong signer mismatch
guard !shaMgr.verify(deviceID: "d1", secret: "sec", challengeResponse: "bad") else {
    throw ProbeError.failed("wrong response")
}

// Legacy static hash still works
let legacy = NonceManager.hash("test", withSecret: "sec")
guard legacy == sha.sign(challenge: "test", secret: "sec") else {
    throw ProbeError.failed("legacy hash")
}

print("ChallengeSignerProbe passed sha=\(sha.algorithm) hmac=\(hmac.algorithm)")
