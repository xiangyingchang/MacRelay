import Foundation
import Security

public final class KeychainDeviceTrustStore: DeviceTrustStore {
    private static let service = "com.macrelay.pairing"
    private static let account = "devices"

    private var devices: [String: DeviceIdentity] = [:]

    public init() {
        try? reload()
    }

    // MARK: - DeviceTrustStore

    public func register(_ device: DeviceIdentity) throws {
        devices[device.deviceID] = device
        try persist()
    }

    public func isTrusted(deviceID: String, deviceSecret: String) -> Bool {
        guard let device = devices[deviceID] else { return false }
        return device.deviceSecret == deviceSecret
    }

    public func list() -> [DeviceIdentity] {
        Array(devices.values)
    }

    public func revoke(deviceID: String) throws {
        guard devices.removeValue(forKey: deviceID) != nil else { return }
        try persist()
    }

    public var count: Int { devices.count }

    // MARK: - Persistence

    public func reload() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            devices = [:]
            return
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainStoreError.readFailed(status: status)
        }
        let array = try JSONDecoder().decode([DeviceIdentity].self, from: data)
        devices = Dictionary(uniqueKeysWithValues: array.map { ($0.deviceID, $0) })
    }

    private func persist() throws {
        let array = Array(devices.values)
        let data = try JSONEncoder().encode(array)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.writeFailed(status: status)
        }
    }
}
