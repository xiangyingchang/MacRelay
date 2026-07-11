import Foundation

// MARK: - Runtime Identifier

/// Identifies which runtime produced an event.
public enum RuntimeIdentifier: String, Codable, CaseIterable {
    case codex = "codex"
    case claudeCode = "claude-code"
    case api = "api"
}

// MARK: - Runtime Event Type

/// Unified event types shared across all runtimes.
/// Maps 1:1 with the Agent Harness lifecycle:
///   session → turn → tool/approval/fileChange → result
public enum RuntimeEventType: String, Codable, CaseIterable {
    // Session lifecycle
    case sessionStarted = "session.started"
    case sessionStopped = "session.stopped"
    case sessionSelected = "session.selected"

    // Turn lifecycle
    case turnStarted = "turn.started"
    case turnCompleted = "turn.completed"
    case turnError = "turn.error"

    // Assistant output
    case assistantDelta = "assistant.delta"
    case assistantMessageCompleted = "assistant.message.completed"

    // Tool calls
    case toolCallRequested = "tool.call.requested"
    case toolCallCompleted = "tool.call.completed"
    case toolCallFailed = "tool.call.failed"

    // Approval
    case approvalRequested = "approval.requested"
    case approvalResolved = "approval.resolved"

    // File changes
    case fileChangeDetected = "file.change.detected"
    case diffUpdated = "diff.updated"

    // Errors & lifecycle
    case error = "error"
    case exited = "exited"
    case settingsUpdated = "settings.updated"
}

// MARK: - Runtime Event Payload

/// Type-safe payload for each event type.
/// Uses associated values so consumers get compile-time safety
/// instead of digging through `[String: Any]`.
public enum RuntimeEventPayload: Codable {
    case sessionStarted(sessionID: String, cwd: String?)
    case sessionStopped(sessionID: String?)
    case sessionSelected(sessionID: String)
    case turnStarted(turnID: String?, input: String?)
    case turnCompleted(turnID: String?)
    case turnError(turnID: String?, message: String)
    case assistantDelta(text: String)
    case assistantMessageCompleted(text: String)
    case toolCall(name: String, params: [String: String]?)
    case toolCallCompleted(name: String, result: String?)
    case toolCallFailed(name: String, error: String)
    case approvalRequested(requestID: Int, tool: String, command: String?, riskLevel: String?)
    case approvalResolved(requestID: Int, decision: String)
    case fileChange(path: String, changeKind: String)
    case diffUpdated(files: [String])
    case error(message: String, code: String?)
    case exited(code: Int32)
    case settingsUpdated(model: String?, effort: String?)
    case generic(method: String, params: [String: String]?)

    // MARK: Codable — manual implementation for associated values

    private enum CodingKey: String {
        case sessionID, cwd, turnID, input, text, name, params
        case result, error, message, code, decision, requestID
        case tool, command, riskLevel, path, changeKind, files
        case model, effort, method
    }

    private var discriminator: String {
        switch self {
        case .sessionStarted: return "sessionStarted"
        case .sessionStopped: return "sessionStopped"
        case .sessionSelected: return "sessionSelected"
        case .turnStarted: return "turnStarted"
        case .turnCompleted: return "turnCompleted"
        case .turnError: return "turnError"
        case .assistantDelta: return "assistantDelta"
        case .assistantMessageCompleted: return "assistantMessageCompleted"
        case .toolCall: return "toolCall"
        case .toolCallCompleted: return "toolCallCompleted"
        case .toolCallFailed: return "toolCallFailed"
        case .approvalRequested: return "approvalRequested"
        case .approvalResolved: return "approvalResolved"
        case .fileChange: return "fileChange"
        case .diffUpdated: return "diffUpdated"
        case .error: return "error"
        case .exited: return "exited"
        case .settingsUpdated: return "settingsUpdated"
        case .generic: return "generic"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(discriminator, forKey: DynamicCodingKey("case"))

        switch self {
        case .sessionStarted(let id, let cwd):
            try container.encode(id, forKey: DynamicCodingKey("sessionID"))
            if let cwd { try container.encode(cwd, forKey: DynamicCodingKey("cwd")) }
        case .sessionStopped(let id):
            if let id { try container.encode(id, forKey: DynamicCodingKey("sessionID")) }
        case .sessionSelected(let id):
            try container.encode(id, forKey: DynamicCodingKey("sessionID"))
        case .turnStarted(let tid, let input):
            if let tid { try container.encode(tid, forKey: DynamicCodingKey("turnID")) }
            if let input { try container.encode(input, forKey: DynamicCodingKey("input")) }
        case .turnCompleted(let tid):
            if let tid { try container.encode(tid, forKey: DynamicCodingKey("turnID")) }
        case .turnError(let tid, let msg):
            if let tid { try container.encode(tid, forKey: DynamicCodingKey("turnID")) }
            try container.encode(msg, forKey: DynamicCodingKey("message"))
        case .assistantDelta(let text):
            try container.encode(text, forKey: DynamicCodingKey("text"))
        case .assistantMessageCompleted(let text):
            try container.encode(text, forKey: DynamicCodingKey("text"))
        case .toolCall(let name, let params):
            try container.encode(name, forKey: DynamicCodingKey("name"))
            if let params { try container.encode(params, forKey: DynamicCodingKey("params")) }
        case .toolCallCompleted(let name, let result):
            try container.encode(name, forKey: DynamicCodingKey("name"))
            if let result { try container.encode(result, forKey: DynamicCodingKey("result")) }
        case .toolCallFailed(let name, let error):
            try container.encode(name, forKey: DynamicCodingKey("name"))
            try container.encode(error, forKey: DynamicCodingKey("error"))
        case .approvalRequested(let rid, let tool, let cmd, let risk):
            try container.encode(rid, forKey: DynamicCodingKey("requestID"))
            try container.encode(tool, forKey: DynamicCodingKey("tool"))
            if let cmd { try container.encode(cmd, forKey: DynamicCodingKey("command")) }
            if let risk { try container.encode(risk, forKey: DynamicCodingKey("riskLevel")) }
        case .approvalResolved(let rid, let decision):
            try container.encode(rid, forKey: DynamicCodingKey("requestID"))
            try container.encode(decision, forKey: DynamicCodingKey("decision"))
        case .fileChange(let path, let kind):
            try container.encode(path, forKey: DynamicCodingKey("path"))
            try container.encode(kind, forKey: DynamicCodingKey("changeKind"))
        case .diffUpdated(let files):
            try container.encode(files, forKey: DynamicCodingKey("files"))
        case .error(let msg, let code):
            try container.encode(msg, forKey: DynamicCodingKey("message"))
            if let code { try container.encode(code, forKey: DynamicCodingKey("code")) }
        case .exited(let code):
            try container.encode(code, forKey: DynamicCodingKey("code"))
        case .settingsUpdated(let model, let effort):
            if let model { try container.encode(model, forKey: DynamicCodingKey("model")) }
            if let effort { try container.encode(effort, forKey: DynamicCodingKey("effort")) }
        case .generic(let method, let params):
            try container.encode(method, forKey: DynamicCodingKey("method"))
            if let params { try container.encode(params, forKey: DynamicCodingKey("params")) }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let `case` = try container.decode(String.self, forKey: DynamicCodingKey("case"))

        switch `case` {
        case "sessionStarted":
            let id = try container.decode(String.self, forKey: DynamicCodingKey("sessionID"))
            let cwd = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("cwd"))
            self = .sessionStarted(sessionID: id, cwd: cwd)
        case "sessionStopped":
            let id = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("sessionID"))
            self = .sessionStopped(sessionID: id)
        case "sessionSelected":
            let id = try container.decode(String.self, forKey: DynamicCodingKey("sessionID"))
            self = .sessionSelected(sessionID: id)
        case "turnStarted":
            let tid = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("turnID"))
            let input = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("input"))
            self = .turnStarted(turnID: tid, input: input)
        case "turnCompleted":
            let tid = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("turnID"))
            self = .turnCompleted(turnID: tid)
        case "turnError":
            let tid = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("turnID"))
            let msg = try container.decode(String.self, forKey: DynamicCodingKey("message"))
            self = .turnError(turnID: tid, message: msg)
        case "assistantDelta":
            let text = try container.decode(String.self, forKey: DynamicCodingKey("text"))
            self = .assistantDelta(text: text)
        case "assistantMessageCompleted":
            let text = try container.decode(String.self, forKey: DynamicCodingKey("text"))
            self = .assistantMessageCompleted(text: text)
        case "toolCall":
            let name = try container.decode(String.self, forKey: DynamicCodingKey("name"))
            let params = try container.decodeIfPresent([String: String].self, forKey: DynamicCodingKey("params"))
            self = .toolCall(name: name, params: params)
        case "toolCallCompleted":
            let name = try container.decode(String.self, forKey: DynamicCodingKey("name"))
            let result = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("result"))
            self = .toolCallCompleted(name: name, result: result)
        case "toolCallFailed":
            let name = try container.decode(String.self, forKey: DynamicCodingKey("name"))
            let error = try container.decode(String.self, forKey: DynamicCodingKey("error"))
            self = .toolCallFailed(name: name, error: error)
        case "approvalRequested":
            let rid = try container.decode(Int.self, forKey: DynamicCodingKey("requestID"))
            let tool = try container.decode(String.self, forKey: DynamicCodingKey("tool"))
            let cmd = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("command"))
            let risk = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("riskLevel"))
            self = .approvalRequested(requestID: rid, tool: tool, command: cmd, riskLevel: risk)
        case "approvalResolved":
            let rid = try container.decode(Int.self, forKey: DynamicCodingKey("requestID"))
            let decision = try container.decode(String.self, forKey: DynamicCodingKey("decision"))
            self = .approvalResolved(requestID: rid, decision: decision)
        case "fileChange":
            let path = try container.decode(String.self, forKey: DynamicCodingKey("path"))
            let kind = try container.decode(String.self, forKey: DynamicCodingKey("changeKind"))
            self = .fileChange(path: path, changeKind: kind)
        case "diffUpdated":
            let files = try container.decode([String].self, forKey: DynamicCodingKey("files"))
            self = .diffUpdated(files: files)
        case "error":
            let msg = try container.decode(String.self, forKey: DynamicCodingKey("message"))
            let code = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("code"))
            self = .error(message: msg, code: code)
        case "exited":
            let code = try container.decode(Int32.self, forKey: DynamicCodingKey("code"))
            self = .exited(code: code)
        case "settingsUpdated":
            let model = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("model"))
            let effort = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("effort"))
            self = .settingsUpdated(model: model, effort: effort)
        case "generic":
            let method = try container.decode(String.self, forKey: DynamicCodingKey("method"))
            let params = try container.decodeIfPresent([String: String].self, forKey: DynamicCodingKey("params"))
            self = .generic(method: method, params: params)
        default:
            self = .generic(method: `case`, params: nil)
        }
    }
}

// MARK: - RuntimeEvent

/// The unified event type for all Agent Harness runtimes.
///
/// Every runtime (Codex, Claude Code, API Agent) emits RuntimeEvents.
/// They flow through:
///   RuntimeEvent → Trace → Reducer → Snapshot → Timeline → Approval → Replay
public struct RuntimeEvent: Codable, Identifiable {
    public let id: String
    public var seq: UInt64?
    public let version: Int
    public let timestamp: Date
    public let sessionID: String?
    public let runID: String?
    public let runtime: RuntimeIdentifier
    public let type: RuntimeEventType
    public let payload: RuntimeEventPayload

    public init(
        id: String = UUID().uuidString,
        seq: UInt64? = nil,
        version: Int = 1,
        timestamp: Date = Date(),
        sessionID: String? = nil,
        runID: String? = nil,
        runtime: RuntimeIdentifier,
        type: RuntimeEventType,
        payload: RuntimeEventPayload
    ) {
        self.id = id
        self.seq = seq
        self.version = version
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.runID = runID
        self.runtime = runtime
        self.type = type
        self.payload = payload
    }
}

// MARK: - Dynamic Coding Key

/// Used for encoding/decoding RuntimeEventPayload associated values.
public struct DynamicCodingKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?

    public init(_ string: String) {
        self.stringValue = string
        self.intValue = nil
    }

    public init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    public init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
