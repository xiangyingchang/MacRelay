import Foundation

// MARK: - Run Status

/// Lifecycle status for an AgentRun.
///
/// State machine:
/// ```
///   created ──► running ──► completed
///                   │
///                   ├─► waitingApproval ──► running
///                   │
///                   ├─► failed
///                   │
///                   ├─► cancelled
///                   │
///                   └─► interrupted  (app crash / unexpected shutdown)
/// ```
public enum RunStatus: String, Codable, Equatable {
    case created
    case running
    case waitingApproval
    case completed
    case failed
    case cancelled
    case interrupted
}

// MARK: - AgentRun

/// Represents a single task execution within a Session.
///
/// A Session is a long-lived context (workspace, settings, history).
/// A Run is a discrete unit of work — one user request to completion.
///
/// Hierarchy: Session ─► Run ─► Turn
///
/// Timeline:
/// - `createdAt`: when the run object was created (always set)
/// - `startedAt`: when the run began executing (set on `start()`)
/// - `finishedAt`: when the run reached a terminal state
///
/// Uses:
/// - Timeline: display runs chronologically
/// - Trace: attach per-run logs and artifacts
/// - History: browse past runs by session
/// - Metadata: persist run state to disk for crash recovery
public struct AgentRun: Codable, Identifiable, Equatable {
    /// Unique identifier for this run.
    public let id: String

    /// The owning session's ID.
    public let sessionID: String

    /// Which runtime executed this run (Codex, Claude Code, etc.).
    public let runtime: RuntimeIdentifier

    /// When the run object was created (always set at init time).
    public let createdAt: Date

    /// When the run began executing (set on `start()` transition).
    /// Nil while status is `.created`.
    public var startedAt: Date?

    /// When the run reached a terminal state (completed/failed/cancelled).
    public var finishedAt: Date?

    /// Current lifecycle status.
    public var status: RunStatus

    /// The user's initial input that started this run.
    public var input: String?

    /// Path to a trace file (optional, for debugging/observability).
    public var tracePath: String?

    /// Brief summary of the run's outcome.
    public var resultSummary: String?

    /// Error summary for failures, separate from resultSummary.
    public var errorSummary: String?

    /// Which provider was used (e.g. "openai", "anthropic").
    public var provider: String?

    /// Which model was used (e.g. "gpt-4o", "claude-sonnet-4-20250514").
    public var model: String?

    /// Count of files changed during this run.
    public var filesChangedCount: Int

    /// Count of tool calls made during this run.
    public var toolCallCount: Int

    /// Count of approvals requested during this run.
    public var approvalCount: Int

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        runtime: RuntimeIdentifier,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        status: RunStatus = .created,
        input: String? = nil,
        tracePath: String? = nil,
        resultSummary: String? = nil,
        errorSummary: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        filesChangedCount: Int = 0,
        toolCallCount: Int = 0,
        approvalCount: Int = 0
    ) {
        self.id = id
        self.sessionID = sessionID
        self.runtime = runtime
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.input = input
        self.tracePath = tracePath
        self.resultSummary = resultSummary
        self.errorSummary = errorSummary
        self.provider = provider
        self.model = model
        self.filesChangedCount = filesChangedCount
        self.toolCallCount = toolCallCount
        self.approvalCount = approvalCount
    }

    // MARK: - State Transitions

    /// Transition to running state. Returns false if not in a valid source state.
    /// Sets `startedAt` to now.
    @discardableResult
    public mutating func start() -> Bool {
        guard status == .created else { return false }
        status = .running
        startedAt = Date()
        return true
    }

    /// Transition to waitingApproval state. Only valid from running.
    public mutating func waitForApproval() -> Bool {
        guard status == .running else { return false }
        status = .waitingApproval
        return true
    }

    /// Resume from waitingApproval back to running.
    public mutating func resume() -> Bool {
        guard status == .waitingApproval else { return false }
        status = .running
        return true
    }

    /// Mark as completed. Only valid from running.
    @discardableResult
    public mutating func complete(summary: String? = nil) -> Bool {
        guard status == .running else { return false }
        status = .completed
        finishedAt = Date()
        if let summary { resultSummary = summary }
        return true
    }

    /// Mark as failed. Valid from running or waitingApproval.
    /// Stores the error in `errorSummary` (and also sets `resultSummary` for backward compat).
    @discardableResult
    public mutating func fail(error: String? = nil) -> Bool {
        guard status == .running || status == .waitingApproval else { return false }
        status = .failed
        finishedAt = Date()
        if let error {
            errorSummary = error
            resultSummary = error // backward compat
        }
        return true
    }

    /// Cancel the run. Valid from created, running, or waitingApproval.
    @discardableResult
    public mutating func cancel() -> Bool {
        guard status == .created || status == .running || status == .waitingApproval else { return false }
        status = .cancelled
        finishedAt = Date()
        return true
    }

    /// Mark as interrupted (app crash / unexpected shutdown).
    /// Valid from any non-terminal state.
    @discardableResult
    public mutating func markInterrupted() -> Bool {
        guard !isTerminal else { return false }
        status = .interrupted
        finishedAt = Date()
        return true
    }

    /// Whether the run is in a terminal state.
    public var isTerminal: Bool {
        switch status {
        case .completed, .failed, .cancelled, .interrupted:
            return true
        case .created, .running, .waitingApproval:
            return false
        }
    }

    /// Duration of the run, or nil if not yet started or finished.
    public var duration: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    /// Wall-clock time from creation to finish, or nil if not yet finished.
    public var totalDuration: TimeInterval? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(createdAt)
    }
}

// MARK: - Run Metadata (for disk persistence)

/// Codable metadata envelope for persisting an AgentRun to `metadata.json`.
///
/// Stored at: `.macrelay/sessions/{runID}/metadata.json`
public struct RunMetadata: Codable, Equatable {
    /// Schema version for forward-compatible migrations.
    public let version: Int

    /// The run this metadata describes.
    public let run: AgentRun

    /// Which session owns this run.
    public let sessionID: String

    /// Path to the trace file (relative or absolute).
    public let tracePath: String?

    /// Arbitrary key-value tags for filtering/search.
    public let tags: [String: String]

    public init(
        version: Int = 1,
        run: AgentRun,
        sessionID: String,
        tracePath: String? = nil,
        tags: [String: String] = [:]
    ) {
        self.version = version
        self.run = run
        self.sessionID = sessionID
        self.tracePath = tracePath
        self.tags = tags
    }
}
