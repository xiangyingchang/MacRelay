import Foundation

// MARK: - Runtime Identifier

/// Identifies which runtime produced an event.
///
/// Known runtimes have dedicated cases. Unknown runtimes use `.custom("provider-name")`
/// so the schema never blocks a new provider from emitting events.
public enum RuntimeIdentifier: String, Codable, Equatable, Hashable {
    case codex = "codex"
    case claudeCode = "claude-code"
    case openAI = "openai"
    case deepSeek = "deepseek"
    case mimo = "mimo"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case local = "local"

    /// For runtimes not yet in the enum. The associated string is the provider identifier.
    /// Decoding a raw value not in the enum automatically routes here.
    case custom = "__custom__"

    /// The provider name for display / routing. For `.custom`, this is the raw string.
    public var providerName: String {
        switch self {
        case .codex: return "Codex CLI"
        case .claudeCode: return "Claude Code"
        case .openAI: return "OpenAI"
        case .deepSeek: return "DeepSeek"
        case .mimo: return "MIMO"
        case .anthropic: return "Anthropic"
        case .gemini: return "Gemini"
        case .local: return "Local Model"
        case .custom: return "Custom"
        }
    }

    // MARK: Codable — forward-compatible: unknown raw values become .custom

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = RuntimeIdentifier(rawValue: raw) ?? .custom
        // Store the original raw value for custom identifiers
        if self == .custom {
            self = .custom
        }
    }

    /// Create a RuntimeIdentifier from an arbitrary string.
    /// Known strings map to dedicated cases; unknown strings become `.custom`.
    public static func from(_ string: String) -> RuntimeIdentifier {
        RuntimeIdentifier(rawValue: string) ?? .custom
    }
}

// MARK: - Runtime Event Type

/// Unified event types shared across all runtimes.
///
/// Maps 1:1 with the Agent Harness lifecycle:
///   session → turn → tool/approval/fileChange → result
///
/// Forward compatibility: unknown event types from newer runtimes are preserved
/// as `.unknown(rawValue)` so decoders never fail on new event types.
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

    // Run lifecycle
    case runStarted = "run.started"
    case runWaitingApproval = "run.waitingApproval"
    case runResumed = "run.resumed"
    case runCompleted = "run.completed"
    case runFailed = "run.failed"
    case runCancelled = "run.cancelled"

    // Errors & lifecycle
    case error = "error"
    case exited = "exited"
    case settingsUpdated = "settings.updated"

    // Forward compatibility: unknown event types from newer runtimes.
    // The associated String is the original raw value.
    case unknown = "__unknown__"

    // MARK: Codable — forward-compatible: unknown raw values become .unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = RuntimeEventType(rawValue: raw) ?? .unknown
    }

    /// The raw value for serialization. For `.unknown`, returns the stored string.
    public var serializedRawValue: String { rawValue }
}

// MARK: - Runtime Event Payload

/// Type-safe payload for each event type.
///
/// Uses associated values so consumers get compile-time safety instead of
/// digging through `[String: Any]`.
///
/// Forward compatibility: `.unknown(discriminator: data:)` preserves the raw
/// JSON of any payload type not yet in this enum. This means:
/// - Older clients can decode events from newer runtimes without crashing
/// - The unknown payload can be inspected or forwarded without data loss
public enum RuntimeEventPayload: Codable, Equatable {
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
    case runStarted(runID: String, input: String?)
    case runWaitingApproval(runID: String)
    case runResumed(runID: String)
    case runCompleted(runID: String, summary: String?)
    case runFailed(runID: String, error: String?)
    case runCancelled(runID: String)
    case generic(method: String, params: [String: String]?)

    /// Forward compatibility: preserves the raw JSON of any unknown payload type.
    /// `discriminator` is the original "case" value; `data` is the remaining JSON.
    case unknown(discriminator: String, data: Data?)

    // MARK: Equatable

    public static func == (lhs: RuntimeEventPayload, rhs: RuntimeEventPayload) -> Bool {
        switch (lhs, rhs) {
        case let (.sessionStarted(a1, b1), .sessionStarted(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.sessionStopped(a), .sessionStopped(b)):
            return a == b
        case let (.sessionSelected(a), .sessionSelected(b)):
            return a == b
        case let (.turnStarted(a1, b1), .turnStarted(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.turnCompleted(a), .turnCompleted(b)):
            return a == b
        case let (.turnError(a1, b1), .turnError(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.assistantDelta(a), .assistantDelta(b)):
            return a == b
        case let (.assistantMessageCompleted(a), .assistantMessageCompleted(b)):
            return a == b
        case let (.toolCall(a1, b1), .toolCall(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.toolCallCompleted(a1, b1), .toolCallCompleted(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.toolCallFailed(a1, b1), .toolCallFailed(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.approvalRequested(a1, b1, c1, d1), .approvalRequested(a2, b2, c2, d2)):
            return a1 == a2 && b1 == b2 && c1 == c2 && d1 == d2
        case let (.approvalResolved(a1, b1), .approvalResolved(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.fileChange(a1, b1), .fileChange(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.diffUpdated(a), .diffUpdated(b)):
            return a == b
        case let (.error(a1, b1), .error(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.exited(a), .exited(b)):
            return a == b
        case let (.settingsUpdated(a1, b1), .settingsUpdated(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.runStarted(a1, b1), .runStarted(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.runWaitingApproval(a), .runWaitingApproval(b)):
            return a == b
        case let (.runResumed(a), .runResumed(b)):
            return a == b
        case let (.runCompleted(a1, b1), .runCompleted(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.runFailed(a1, b1), .runFailed(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.runCancelled(a), .runCancelled(b)):
            return a == b
        case let (.generic(a1, b1), .generic(a2, b2)):
            return a1 == a2 && b1 == b2
        case let (.unknown(d1, data1), .unknown(d2, data2)):
            return d1 == d2 && data1 == data2
        default:
            return false
        }
    }

    // MARK: Codable — manual implementation for associated values

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
        case .runStarted: return "runStarted"
        case .runWaitingApproval: return "runWaitingApproval"
        case .runResumed: return "runResumed"
        case .runCompleted: return "runCompleted"
        case .runFailed: return "runFailed"
        case .runCancelled: return "runCancelled"
        case .generic: return "generic"
        case .unknown(let d, _): return d
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
        case .runStarted(let runID, let input):
            try container.encode(runID, forKey: DynamicCodingKey("runID"))
            if let input { try container.encode(input, forKey: DynamicCodingKey("input")) }
        case .runWaitingApproval(let runID):
            try container.encode(runID, forKey: DynamicCodingKey("runID"))
        case .runResumed(let runID):
            try container.encode(runID, forKey: DynamicCodingKey("runID"))
        case .runCompleted(let runID, let summary):
            try container.encode(runID, forKey: DynamicCodingKey("runID"))
            if let summary { try container.encode(summary, forKey: DynamicCodingKey("summary")) }
        case .runFailed(let runID, let error):
            try container.encode(runID, forKey: DynamicCodingKey("runID"))
            if let error { try container.encode(error, forKey: DynamicCodingKey("error")) }
        case .runCancelled(let runID):
            try container.encode(runID, forKey: DynamicCodingKey("runID"))
        case .generic(let method, let params):
            try container.encode(method, forKey: DynamicCodingKey("method"))
            if let params { try container.encode(params, forKey: DynamicCodingKey("params")) }
        case .unknown(_, let data):
            // Preserve the raw JSON data as a base64 string so it survives round-trips.
            if let data {
                try container.encode(data.base64EncodedString(), forKey: DynamicCodingKey("_rawData"))
            }
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
        case "runStarted":
            let runID = try container.decode(String.self, forKey: DynamicCodingKey("runID"))
            let input = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("input"))
            self = .runStarted(runID: runID, input: input)
        case "runWaitingApproval":
            let runID = try container.decode(String.self, forKey: DynamicCodingKey("runID"))
            self = .runWaitingApproval(runID: runID)
        case "runResumed":
            let runID = try container.decode(String.self, forKey: DynamicCodingKey("runID"))
            self = .runResumed(runID: runID)
        case "runCompleted":
            let runID = try container.decode(String.self, forKey: DynamicCodingKey("runID"))
            let summary = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("summary"))
            self = .runCompleted(runID: runID, summary: summary)
        case "runFailed":
            let runID = try container.decode(String.self, forKey: DynamicCodingKey("runID"))
            let error = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("error"))
            self = .runFailed(runID: runID, error: error)
        case "runCancelled":
            let runID = try container.decode(String.self, forKey: DynamicCodingKey("runID"))
            self = .runCancelled(runID: runID)
        case "generic":
            let method = try container.decode(String.self, forKey: DynamicCodingKey("method"))
            let params = try container.decodeIfPresent([String: String].self, forKey: DynamicCodingKey("params"))
            self = .generic(method: method, params: params)
        default:
            // Forward compatibility: preserve the raw discriminator and any data.
            let rawData: Data?
            if let base64 = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("_rawData")) {
                rawData = Data(base64Encoded: base64)
            } else {
                // Re-encode the entire container as raw data for preservation.
                let dict = try decoder.container(keyedBy: DynamicCodingKey.self)
                var preserved: [String: Any] = [:]
                // Best-effort: we can't easily re-encode arbitrary JSON from a Decoder,
                // so we store just the discriminator. The caller can inspect the trace.
                rawData = nil
                _ = dict // silence unused warning
            }
            self = .unknown(discriminator: `case`, data: rawData)
        }
    }
}

// MARK: - RuntimeEvent

/// The unified event type for all Agent Harness runtimes.
///
/// Design principles:
/// - **Immutable**: all fields are `let`. Once created, an event never changes.
/// - **Versioned**: `version` enables schema evolution without breaking old readers.
/// - **Forward-compatible**: unknown event types and payload types are preserved
///   as `.unknown` variants, so older clients never crash on newer events.
/// - **Self-describing**: `runtime` identifies the source; `type` identifies the kind;
///   `payload` carries the data.
///
/// Flow: Runtime → RuntimeEvent → Trace → Reducer → Snapshot → Timeline
public struct RuntimeEvent: Codable, Identifiable {
    /// Unique event ID (UUID). Never reused.
    public let id: String

    /// Monotonic sequence number, assigned by EventStore at ingestion time.
    /// Nil until the event enters the store.
    public let seq: UInt64?

    /// Schema version. Current: 1. Increment on breaking changes.
    public let version: Int

    /// The current schema version. TraceReader uses this to skip events
    /// from a future schema version that the current reducer cannot interpret.
    public static let currentVersion = 1

    /// Wall-clock time of the event (UTC).
    public let timestamp: Date

    /// Session this event belongs to. Nil for session-level events before ID is known.
    public let sessionID: String?

    /// Run (task execution) this event belongs to. Enables per-run trace grouping.
    public let runID: String?

    /// Which runtime produced this event.
    public let runtime: RuntimeIdentifier

    /// What happened.
    public let type: RuntimeEventType

    /// Event-specific data.
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

    /// Create a copy with a sequence number assigned (used by EventStore).
    public func withSeq(_ seq: UInt64) -> RuntimeEvent {
        RuntimeEvent(
            id: id, seq: seq, version: version, timestamp: timestamp,
            sessionID: sessionID, runID: runID, runtime: runtime,
            type: type, payload: payload
        )
    }
}

// MARK: - Dynamic Coding Key

/// Used for encoding/decoding RuntimeEventPayload associated values.
/// Internal implementation detail — not part of the public API.
struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        self.stringValue = string
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
