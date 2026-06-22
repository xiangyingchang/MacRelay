import AgentClientCore
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let m): return m } }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ProbeError.failed(message) }
}

let store = MemoryDeviceTrustStore()

let iphone = DeviceIdentity(deviceID: "iphone-1", deviceSecret: "secret-abc", deviceName: "Haoshi iPhone")
try store.register(iphone)
try expect(store.count == 1, "register one device")
try expect(store.isTrusted(deviceID: "iphone-1", deviceSecret: "secret-abc"), "trusted with correct secret")
try expect(!store.isTrusted(deviceID: "iphone-1", deviceSecret: "wrong"), "not trusted with wrong secret")
try expect(!store.isTrusted(deviceID: "nonexistent", deviceSecret: "secret-abc"), "unknown device")

let list = store.list()
try expect(list.count == 1, "list one")
try expect(list[0].deviceName == "Haoshi iPhone", "device name")

try store.revoke(deviceID: "iphone-1")
try expect(store.count == 0, "revoke removes device")
try expect(!store.isTrusted(deviceID: "iphone-1", deviceSecret: "secret-abc"), "not trusted after revoke")

// --- persistence tests ---
let kcStore = KeychainDeviceTrustStore()
let kcDevice = DeviceIdentity(deviceID: "kc-iphone", deviceSecret: "kc-secret", deviceName: "Keychain iPhone")
try kcStore.register(kcDevice)
try expect(kcStore.count == 1, "keychain register")

// simulate restart by creating a new KeychainDeviceTrustStore
let kcStore2 = KeychainDeviceTrustStore()
try expect(kcStore2.count == 1, "keychain restart reload")
try expect(kcStore2.isTrusted(deviceID: "kc-iphone", deviceSecret: "kc-secret"), "keychain restart trusted")
try expect(!kcStore2.isTrusted(deviceID: "kc-iphone", deviceSecret: "wrong"), "keychain restart wrong secret")

// revoke and check via new instance
try kcStore2.revoke(deviceID: "kc-iphone")
let kcStore3 = KeychainDeviceTrustStore()
try expect(kcStore3.count == 0, "keychain revoke persists")

print("DeviceTrustStoreProbe passed memory=\(list.count) persistent=true")
