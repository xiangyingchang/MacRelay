import AgentClientCore
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let m): return m } }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ProbeError.failed(message) }
}

// ---- Test 1: store → reload (simulates App restart) ----
let store1 = KeychainPairingCredentialStore(storeID: "keychain-probe-1")
try store1.store(token: "tk-key-1", claim: "cl-key-1", expiresAt: Date().addingTimeInterval(600))
try expect(store1.token == "tk-key-1", "store1 token")
try expect(store1.claim == "cl-key-1", "store1 claim")
try expect(store1.deviceID != nil, "store1 deviceID")
try expect(store1.deviceSecret != nil, "store1 deviceSecret")

let store2 = KeychainPairingCredentialStore(storeID: "keychain-probe-2")
try expect(store2.token == "tk-key-1", "reload token after restart")
try expect(store2.claim == "cl-key-1", "reload claim after restart")
try expect(store2.deviceID == store1.deviceID, "deviceID stable across restarts")
try expect(store2.deviceSecret == store1.deviceSecret, "deviceSecret stable across restarts")

// ---- Test 2: rotate (store again) ----
try store2.store(token: "tk-key-2", claim: "cl-key-2", expiresAt: Date().addingTimeInterval(600))
try expect(store2.token == "tk-key-2", "rotate token")
try expect(store2.deviceID == store1.deviceID, "deviceID preserved across rotate")

let store3 = KeychainPairingCredentialStore(storeID: "keychain-probe-3")
try expect(store3.token == "tk-key-2", "restart after rotate loads new token")

// ---- Test 3: revoke ----
try store3.revoke()
try expect(store3.token == nil, "revoke clears token")
try expect(store3.claim == nil, "revoke clears claim")

let store4 = KeychainPairingCredentialStore(storeID: "keychain-probe-4")
try expect(store4.token == nil, "restart after revoke should be empty")

// ---- Test 4: Memory store still works ----
let mem = MemoryPairingCredentialStore(storeID: "mem-probe")
try mem.store(token: "mem-tk", claim: "mem-cl", expiresAt: Date().addingTimeInterval(600))
try expect(mem.token == "mem-tk", "memory store token")
try mem.revoke()
try expect(mem.token == nil, "memory store revoke")

print("KeychainPairingCredentialStoreProbe passed store=\(store4.storeID)")
