import Foundation

// MARK: - Timeline Item Types

/// The kind of a timeline entry. Each maps to a distinct UI cell
/// on iOS, macOS, and Web — but this enum carries zero UI knowledge.
public enum TimelineItemType: String, Codable, Equatable, CaseIterable {
    case userMessage
    case assistantMessage
    case thinking
    case toolCall
    case approval
    case fileChange
    case error
    case finalResult
}

/// Status of a single tool-call lifecycle.
public enum ToolCallStatus: String, Codable, Equatable {
    case requested
    case running
    case completed
    case failed
}

/// Status of an approval request.
public enum ApprovalStatus: String, Codable, Equatable {
    case pending
    case accepted
    case rejected
}

// MARK: - TimelineItem

/// A single, immutable entry on a session timeline.
///
/// `TimelineItem` is the **view-model primitive** consumed by every platform
/// renderer.  It carries no SwiftUI, UIKit, or DOM types — just data that
/// any consumer can turn into the right cell.
public struct TimelineItem: Codable, Identifiable, Equatable {
    /// Stable ID (UUID by default; caller can supply a deterministic one).
    public let id: String

    /// Discriminator for fast filtering / grouping.
    public let type: TimelineItemType

    /// Wall-clock time the item was created (UTC).
    public let timestamp: Date

    /// Type-specific payload.
    public let data: TimelineItemData

    public init(
        id: String = UUID().uuidString,
        type: TimelineItemType,
        timestamp: Date = Date(),
        data: TimelineItemData
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.data = data
    }
}

// MARK: - TimelineItemData

/// Type-safe payload for each timeline item kind.
///
/// Uses associated values so consumers get compile-time safety instead of
/// digging through dictionaries.
public enum TimelineItemData: Codable, Equatable {
    case userMessage(text: String)
    case assistantMessage(text: String)
    case thinking(text: String)
    case toolCall(name: String, status: ToolCallStatus, input: String?, output: String?)
    case approval(requestID: Int, tool: String, command: String?, status: ApprovalStatus)
    case fileChange(path: String, changeKind: String)
    case error(message: String, code: String?)
    case finalResult(text: String)

    // MARK: Equatable

    public static func == (lhs: TimelineItemData, rhs: TimelineItemData) -> Bool {
        switch (lhs, rhs) {
        case let (.userMessage(a), .userMessage(b)):             return a == b
        case let (.assistantMessage(a), .assistantMessage(b)):   return a == b
        case let (.thinking(a), .thinking(b)):                   return a == b
        case let (.toolCall(n1, s1, i1, o1), .toolCall(n2, s2, i2, o2)):
            return n1 == n2 && s1 == s2 && i1 == i2 && o1 == o2
        case let (.approval(r1, t1, c1, s1), .approval(r2, t2, c2, s2)):
            return r1 == r2 && t1 == t2 && c1 == c2 && s1 == s2
        case let (.fileChange(p1, k1), .fileChange(p2, k2)):   return p1 == p2 && k1 == k2
        case let (.error(m1, c1), .error(m2, c2)):             return m1 == m2 && c1 == c2
        case let (.finalResult(a), .finalResult(b)):            return a == b
        default: return false
        }
    }

    // MARK: Codable — manual for associated values

    private var discriminator: String {
        switch self {
        case .userMessage:      return "userMessage"
        case .assistantMessage: return "assistantMessage"
        case .thinking:         return "thinking"
        case .toolCall:         return "toolCall"
        case .approval:         return "approval"
        case .fileChange:       return "fileChange"
        case .error:            return "error"
        case .finalResult:      return "finalResult"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicCodingKey.self)
        try c.encode(discriminator, forKey: DynamicCodingKey("case"))

        switch self {
        case .userMessage(let text):
            try c.encode(text, forKey: DynamicCodingKey("text"))
        case .assistantMessage(let text):
            try c.encode(text, forKey: DynamicCodingKey("text"))
        case .thinking(let text):
            try c.encode(text, forKey: DynamicCodingKey("text"))
        case .toolCall(let name, let status, let input, let output):
            try c.encode(name, forKey: DynamicCodingKey("name"))
            try c.encode(status, forKey: DynamicCodingKey("status"))
            if let input  { try c.encode(input,  forKey: DynamicCodingKey("input")) }
            if let output { try c.encode(output, forKey: DynamicCodingKey("output")) }
        case .approval(let rid, let tool, let cmd, let status):
            try c.encode(rid, forKey: DynamicCodingKey("requestID"))
            try c.encode(tool, forKey: DynamicCodingKey("tool"))
            if let cmd { try c.encode(cmd, forKey: DynamicCodingKey("command")) }
            try c.encode(status, forKey: DynamicCodingKey("status"))
        case .fileChange(let path, let kind):
            try c.encode(path, forKey: DynamicCodingKey("path"))
            try c.encode(kind, forKey: DynamicCodingKey("changeKind"))
        case .error(let msg, let code):
            try c.encode(msg, forKey: DynamicCodingKey("message"))
            if let code { try c.encode(code, forKey: DynamicCodingKey("code")) }
        case .finalResult(let text):
            try c.encode(text, forKey: DynamicCodingKey("text"))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicCodingKey.self)
        let tag = try c.decode(String.self, forKey: DynamicCodingKey("case"))

        switch tag {
        case "userMessage":
            self = .userMessage(text: try c.decode(String.self, forKey: DynamicCodingKey("text")))
        case "assistantMessage":
            self = .assistantMessage(text: try c.decode(String.self, forKey: DynamicCodingKey("text")))
        case "thinking":
            self = .thinking(text: try c.decode(String.self, forKey: DynamicCodingKey("text")))
        case "toolCall":
            self = .toolCall(
                name:   try c.decode(String.self, forKey: DynamicCodingKey("name")),
                status: try c.decode(ToolCallStatus.self, forKey: DynamicCodingKey("status")),
                input:  try c.decodeIfPresent(String.self, forKey: DynamicCodingKey("input")),
                output: try c.decodeIfPresent(String.self, forKey: DynamicCodingKey("output"))
            )
        case "approval":
            self = .approval(
                requestID: try c.decode(Int.self, forKey: DynamicCodingKey("requestID")),
                tool:      try c.decode(String.self, forKey: DynamicCodingKey("tool")),
                command:   try c.decodeIfPresent(String.self, forKey: DynamicCodingKey("command")),
                status:    try c.decode(ApprovalStatus.self, forKey: DynamicCodingKey("status"))
            )
        case "fileChange":
            self = .fileChange(
                path:      try c.decode(String.self, forKey: DynamicCodingKey("path")),
                changeKind: try c.decode(String.self, forKey: DynamicCodingKey("changeKind"))
            )
        case "error":
            self = .error(
                message: try c.decode(String.self, forKey: DynamicCodingKey("message")),
                code:    try c.decodeIfPresent(String.self, forKey: DynamicCodingKey("code"))
            )
        case "finalResult":
            self = .finalResult(text: try c.decode(String.self, forKey: DynamicCodingKey("text")))
        default:
            // Forward compatibility: treat unknown discriminators as error.
            self = .error(message: "Unknown timeline item: \(tag)", code: nil)
        }
    }
}
