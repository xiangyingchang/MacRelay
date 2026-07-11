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
///                   └─► cancelled
/// ```
public enum RunStatus: String, Codable, Equatable {
    case created
    case running
    case waitingApproval
    case completed
    case failed
    case cancelled
}

// MARK: - AgentRun

/// Represents a single task execution within a Session.
///
/// A Session is a long-lived context (workspace, settings, history).
/// A Run is a discrete unit of work — one user request to completion.
///
/// Hierarchy: Session ─► Run ─► Turn
///
/// Future uses:
/// - Timeline: display runs chronologically
/// - Trace: attach per-run logs and artifacts
/// - History: browse past runs by session
public struct AgentRun: Codable, Identifiable, Equatable {
    /// Unique identifier for this run.
    public let id: String

    /// The owning session's ID.
    public let sessionID: String

    /// Which runtime executed this run (Codex, Claude Code, etc.).
    public let runtime: RuntimeIdentifier

    /// When the run was created.
    public let startedAt: Date

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

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        runtime: RuntimeIdentifier,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        status: RunStatus = .created,
        input: String? = nil,
        tracePath: String? = nil,
        resultSummary: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.runtime = runtime
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.input = input
        self.tracePath = tracePath
        self.resultSummary = resultSummary
    }

    // MARK: - State Transitions

    /// Transition to running state. Returns false if not in a valid source state.
    public mutating func start() -> Bool {
        guard status == .created else { return false }
        status = .running
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
    @discardableResult
    public mutating func fail(error: String? = nil) -> Bool {
        guard status == .running || status == .waitingApproval else { return false }
        status = .failed
        finishedAt = Date()
        if let error { resultSummary = error }
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

    /// Whether the run is in a terminal state.
    public var isTerminal: Bool {
        switch status {
        case .completed, .failed, .cancelled:
            return true
        case .created, .running, .waitingApproval:
            return false
        }
    }

    /// Duration of the run, or nil if not yet finished.
    public var duration: TimeInterval? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }
}
