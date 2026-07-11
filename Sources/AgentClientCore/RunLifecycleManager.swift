import Foundation

// MARK: - RunLifecycleManager

/// Maps RuntimeEvent types to AgentRun state transitions.
///
/// Usage:
/// ```swift
/// var manager = RunLifecycleManager(sessionID: "s1", runtime: .claudeCode)
/// for event in events {
///     if let run = manager.apply(event: event) {
///         // persist the updated run
///     }
/// }
/// ```
///
/// The manager owns a mutable `currentRun` that tracks the active run.
/// When a terminal state is reached, `apply()` returns the completed run
/// and clears `currentRun` so a new run can begin.
public struct RunLifecycleManager {
    /// The currently active run, if any.
    public private(set) var currentRun: AgentRun?

    /// Session ID for new runs.
    public let sessionID: String

    /// Default runtime for new runs.
    public let runtime: RuntimeIdentifier

    public init(sessionID: String, runtime: RuntimeIdentifier) {
        self.sessionID = sessionID
        self.runtime = runtime
    }

    /// Apply a RuntimeEvent and return the updated run if the event caused a state change.
    ///
    /// Returns the run when:
    /// - A new run is created (run.started)
    /// - The run transitions to a new state (approval, completion, failure, cancellation)
    /// - The run reaches a terminal state (the run is also moved to `completedRuns` internally)
    ///
    /// Returns nil when:
    /// - The event is not a run-lifecycle event
    /// - The event's runID does not match the current run
    /// - The state transition is invalid
    @discardableResult
    public mutating func apply(event: RuntimeEvent) -> AgentRun? {
        switch event.type {
        case .runStarted:
            return handleRunStarted(event: event)

        case .approvalRequested:
            return handleApprovalRequested(event: event)

        case .approvalResolved:
            return handleApprovalResolved(event: event)

        case .runCompleted:
            return handleRunCompleted(event: event)

        case .runFailed:
            return handleRunFailed(event: event)

        case .runCancelled:
            return handleRunCancelled(event: event)

        case .fileChangeDetected:
            return handleFileChange(event: event)

        case .toolCallRequested:
            return handleToolCall(event: event)

        case .settingsUpdated:
            return handleSettingsUpdated(event: event)

        case .exited:
            return handleExited(event: event)

        default:
            return nil
        }
    }

    /// Force the current run into interrupted state (e.g. on app startup after crash).
    /// Returns the interrupted run, or nil if there is no active run.
    @discardableResult
    public mutating func markInterrupted() -> AgentRun? {
        guard var run = currentRun else { return nil }
        guard run.markInterrupted() else { return nil }
        currentRun = nil
        return run
    }

    // MARK: - Event Handlers

    private mutating func handleRunStarted(event: RuntimeEvent) -> AgentRun? {
        guard case let .runStarted(runID, input) = event.payload else { return nil }

        let run = AgentRun(
            id: runID,
            sessionID: event.sessionID ?? sessionID,
            runtime: event.runtime,
            status: .running,
            input: input,
            provider: event.runtime.providerName
        )
        currentRun = run
        return run
    }

    private mutating func handleApprovalRequested(event: RuntimeEvent) -> AgentRun? {
        guard case let .approvalRequested(requestID, _, _, _) = event.payload else { return nil }
        guard let runID = event.runID, currentRun?.id == runID else { return nil }
        guard currentRun?.waitForApproval() == true else { return nil }
        currentRun?.approvalCount += 1
        return currentRun
    }

    private mutating func handleApprovalResolved(event: RuntimeEvent) -> AgentRun? {
        guard case .approvalResolved = event.payload else { return nil }
        guard let runID = event.runID, currentRun?.id == runID else { return nil }
        guard currentRun?.resume() == true else { return nil }
        return currentRun
    }

    private mutating func handleRunCompleted(event: RuntimeEvent) -> AgentRun? {
        guard case let .runCompleted(runID, summary) = event.payload else { return nil }
        guard currentRun?.id == runID else { return nil }
        guard currentRun?.complete(summary: summary) == true else { return nil }
        let run = currentRun
        currentRun = nil
        return run
    }

    private mutating func handleRunFailed(event: RuntimeEvent) -> AgentRun? {
        guard case let .runFailed(runID, error) = event.payload else { return nil }
        guard currentRun?.id == runID else { return nil }
        guard currentRun?.fail(error: error) == true else { return nil }
        let run = currentRun
        currentRun = nil
        return run
    }

    private mutating func handleRunCancelled(event: RuntimeEvent) -> AgentRun? {
        guard case let .runCancelled(runID) = event.payload else { return nil }
        guard currentRun?.id == runID else { return nil }
        guard currentRun?.cancel() == true else { return nil }
        let run = currentRun
        currentRun = nil
        return run
    }

    private mutating func handleFileChange(event: RuntimeEvent) -> AgentRun? {
        guard case .fileChange = event.payload else { return nil }
        guard currentRun != nil else { return nil }
        currentRun?.filesChangedCount += 1
        return currentRun
    }

    private mutating func handleToolCall(event: RuntimeEvent) -> AgentRun? {
        guard case .toolCall = event.payload else { return nil }
        guard currentRun != nil else { return nil }
        currentRun?.toolCallCount += 1
        return currentRun
    }

    private mutating func handleSettingsUpdated(event: RuntimeEvent) -> AgentRun? {
        guard case let .settingsUpdated(model, _) = event.payload else { return nil }
        guard currentRun != nil else { return nil }
        if let model { currentRun?.model = model }
        return currentRun
    }

    private mutating func handleExited(event: RuntimeEvent) -> AgentRun? {
        guard var run = currentRun else { return nil }
        // If the run is still active when the process exits, mark as interrupted
        if !run.isTerminal {
            run.markInterrupted()
            currentRun = nil
            return run
        }
        return nil
    }
}
