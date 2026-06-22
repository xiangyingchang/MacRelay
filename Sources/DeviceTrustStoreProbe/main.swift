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

print("DeviceTrustStoreProbe passed devices=\(list.count)")
