import AgentClientCore
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let m): return m } }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ProbeError.failed(message) }
}

// Test 1: store → values available
let store = MemoryPairingCredentialStore(storeID: "fixture-probe")
try store.store(token: "tk-1", claim: "cl-1", expiresAt: Date().addingTimeInterval(600))
try expect(store.token == "tk-1", "store token")
try expect(store.claim == "cl-1", "store claim")
try expect(store.expiresAt != nil, "store expiresAt")
try expect(store.claimedAt == nil, "store not yet claimed")
try store.reload()
try expect(store.token == "tk-1", "reload preserves token")

// Test 2: revoke → values cleared
try store.revoke()
try expect(store.token == nil, "revoke clears token")
try expect(store.claim == nil, "revoke clears claim")
try expect(store.expiresAt == nil, "revoke clears expiresAt")

// Test 3: rotate pattern via store (simulates HTTPServer.rotatePairingToken)
try store.store(token: "tk-2", claim: "cl-2", expiresAt: Date().addingTimeInterval(600))
try expect(store.token == "tk-2", "new token after rotate.store")
try expect(store.claim == "cl-2", "new claim after rotate.store")
try store.revoke()
try expect(store.token == nil, "old token revoked after rotate")
try store.store(token: "tk-3", claim: "cl-3", expiresAt: Date().addingTimeInterval(600))
try expect(store.token == "tk-3", "newest token available")

print("PairingCredentialStoreFixtureProbe passed store=\(store.storeID)")
