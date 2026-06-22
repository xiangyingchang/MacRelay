import Foundation
import Security

/// macOS Keychain-backed pairing credential store.
///
/// Stores token, claim, expiry, and device identity as a single encrypted JSON
/// item under the `com.macrelay.pairing` service.  Survives App restarts and
/// never touches git.
public final class KeychainPairingCredentialStore: PairingCredentialStore {
    private static let service = "com.macrelay.pairing"
    private static let account = "default"

    public private(set) var token: String?
    public private(set) var claim: String?
    public private(set) var expiresAt: Date?
    public var claimedAt: Date?
    public private(set) var deviceID: String?
    public private(set) var deviceSecret: String?
    public let storeID: String

    private let encoder = JSONEncoder()

    public init(storeID: String = "keychain-\(UUID().uuidString.prefix(8))") {
        self.storeID = storeID
        try? reload()
    }

    // MARK: - Persistence

    private struct StoredPayload: Codable {
        var token: String
        var claim: String
        var expiresAt: Date
        var deviceID: String
        var deviceSecret: String
    }

    public func store(token: String, claim: String, expiresAt: Date) throws {
        let deviceID = self.deviceID ?? UUID().uuidString
        let deviceSecret = self.deviceSecret ?? randomSecret()
        let payload = StoredPayload(
            token: token,
            claim: claim,
            expiresAt: expiresAt,
            deviceID: deviceID,
            deviceSecret: deviceSecret
        )
        let data = try encoder.encode(payload)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]

        // Delete any existing item before writing
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.writeFailed(status: status)
        }

        self.token = token
        self.claim = claim
        self.expiresAt = expiresAt
        self.deviceID = deviceID
        self.deviceSecret = deviceSecret
    }

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

        // errSecItemNotFound is fine — no stored credentials yet
        if status == errSecItemNotFound { return }

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainStoreError.readFailed(status: status)
        }

        let payload = try JSONDecoder().decode(StoredPayload.self, from: data)
        self.token = payload.token
        self.claim = payload.claim
        self.expiresAt = payload.expiresAt
        self.deviceID = payload.deviceID
        self.deviceSecret = payload.deviceSecret
    }

    public func revoke() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainStoreError.deleteFailed(status: status)
        }
        token = nil
        claim = nil
        expiresAt = nil
        claimedAt = nil
    }

    private func randomSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}

public enum KeychainStoreError: Error, CustomStringConvertible {
    case writeFailed(status: OSStatus)
    case readFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)

    public var description: String {
        switch self {
        case .writeFailed(let s): return "Keychain write failed (\(s))"
        case .readFailed(let s): return "Keychain read failed (\(s))"
        case .deleteFailed(let s): return "Keychain delete failed (\(s))"
        }
    }
}
