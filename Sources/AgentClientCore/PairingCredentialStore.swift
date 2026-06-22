import Foundation

public protocol PairingCredentialStore: AnyObject {
    var token: String? { get }
    var claim: String? { get }
    var expiresAt: Date? { get }
    var claimedAt: Date? { get set }
    var storeID: String { get }

    func store(token: String, claim: String, expiresAt: Date) throws
    func reload() throws
    func revoke() throws
}

public final class MemoryPairingCredentialStore: PairingCredentialStore {
    public private(set) var token: String?
    public private(set) var claim: String?
    public private(set) var expiresAt: Date?
    public var claimedAt: Date?
    public let storeID: String

    public init(storeID: String = UUID().uuidString) {
        self.storeID = storeID
    }

    public func store(token: String, claim: String, expiresAt: Date) throws {
        self.token = token
        self.claim = claim
        self.expiresAt = expiresAt
    }

    public func reload() throws {
        // Memory store always returns the latest stored values.
    }

    public func revoke() throws {
        token = nil
        claim = nil
        expiresAt = nil
        claimedAt = nil
    }
}
