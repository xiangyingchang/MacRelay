import Foundation

public struct CodexApprovalRequest {
    public let requestID: Int
    public let method: String
    public let threadID: String?
    public let turnID: String?
    public let itemID: String?
    public let command: Any?
    public let reason: String?
    public let availableDecisions: [String]
    public let rawParams: [String: Any]?

    public init?(requestID: Int, method: String, params: [String: Any]?) {
        guard method.contains("requestApproval") else {
            return nil
        }

        self.requestID = requestID
        self.method = method
        self.threadID = params?["threadId"] as? String
        self.turnID = params?["turnId"] as? String
        self.itemID = params?["itemId"] as? String
        self.command = params?["command"]
        self.reason = params?["reason"] as? String
        self.availableDecisions = params?["availableDecisions"] as? [String] ?? []
        self.rawParams = params
    }

    public var defaultAcceptDecision: String {
        if availableDecisions.contains("accept") {
            return "accept"
        }
        if availableDecisions.contains("approved") {
            return "approved"
        }
        return availableDecisions.first ?? "accept"
    }

    public var summary: [String: Any] {
        [
            "requestID": requestID,
            "method": method,
            "threadID": threadID as Any,
            "turnID": turnID as Any,
            "itemID": itemID as Any,
            "command": command as Any,
            "reason": reason as Any,
            "availableDecisions": availableDecisions
        ]
    }
}
