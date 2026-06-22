import Foundation

public struct DeviceIdentity: Codable, Equatable {
    public let deviceID: String
    public let deviceSecret: String
    public let deviceName: String
    public let registeredAt: Date

    public init(deviceID: String, deviceSecret: String, deviceName: String, registeredAt: Date = Date()) {
        self.deviceID = deviceID
        self.deviceSecret = deviceSecret
        self.deviceName = deviceName
        self.registeredAt = registeredAt
    }
}

public protocol DeviceTrustStore: AnyObject {
    func register(_ device: DeviceIdentity) throws
    func isTrusted(deviceID: String, deviceSecret: String) -> Bool
    func list() -> [DeviceIdentity]
    func revoke(deviceID: String) throws
    var count: Int { get }
}

public final class MemoryDeviceTrustStore: DeviceTrustStore {
    private var devices: [String: DeviceIdentity] = [:]

    public init() {}

    public func register(_ device: DeviceIdentity) throws {
        devices[device.deviceID] = device
    }

    public func isTrusted(deviceID: String, deviceSecret: String) -> Bool {
        guard let device = devices[deviceID] else { return false }
        return device.deviceSecret == deviceSecret
    }

    public func list() -> [DeviceIdentity] {
        Array(devices.values)
    }

    public func revoke(deviceID: String) throws {
        devices.removeValue(forKey: deviceID)
    }

    public var count: Int { devices.count }
}
