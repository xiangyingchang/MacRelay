import Foundation

public struct CodexTurnDiffUpdated {
    public let threadID: String?
    public let turnID: String?
    public let diff: String
    public let rawParams: [String: Any]

    public init?(method: String, params: [String: Any]?) {
        guard method == "turn/diff/updated", let params else {
            return nil
        }

        self.threadID = params["threadId"] as? String
        self.turnID = params["turnId"] as? String
        self.diff = params["diff"] as? String ?? ""
        self.rawParams = params
    }

    public var summary: [String: Any] {
        [
            "threadID": threadID as Any,
            "turnID": turnID as Any,
            "diffLength": diff.count,
            "changedFiles": changedFiles
        ]
    }

    public var changedFiles: [String] {
        diff
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.hasPrefix("diff --git ") else { return nil }
                let parts = line.split(separator: " ")
                guard parts.count >= 4 else { return nil }
                let bPath = String(parts[3])
                return bPath.hasPrefix("b/") ? String(bPath.dropFirst(2)) : bPath
            }
    }
}

public struct CodexFileChangeUpdated {
    public let method: String
    public let threadID: String?
    public let turnID: String?
    public let itemID: String?
    public let path: String?
    public let changeKind: String?
    public let diff: String?
    public let rawItem: [String: Any]

    public init?(method: String, params: [String: Any]?) {
        guard method == "item/started" || method == "item/completed",
              let params,
              let item = params["item"] as? [String: Any],
              item["type"] as? String == "fileChange" else {
            return nil
        }

        self.method = method
        self.threadID = params["threadId"] as? String
        self.turnID = params["turnId"] as? String
        self.itemID = item["id"] as? String
        self.path = Self.extractPath(from: item)
        self.changeKind = item["changeKind"] as? String ?? item["kind"] as? String ?? item["status"] as? String
        self.diff = item["diff"] as? String ?? item["unifiedDiff"] as? String
        self.rawItem = item
    }

    public var summary: [String: Any] {
        [
            "method": method,
            "threadID": threadID as Any,
            "turnID": turnID as Any,
            "itemID": itemID as Any,
            "path": path as Any,
            "changeKind": changeKind as Any,
            "diffLength": diff?.count ?? 0
        ]
    }

    private static func extractPath(from item: [String: Any]) -> String? {
        if let path = item["path"] as? String {
            return path
        }
        if let filePath = item["filePath"] as? String {
            return filePath
        }
        if let uri = item["uri"] as? String {
            return uri
        }
        if let changes = item["changes"] as? [[String: Any]] {
            return changes.compactMap { change in
                change["path"] as? String ?? change["filePath"] as? String
            }.first
        }
        return nil
    }
}
