import Foundation

// MARK: - Recovery Warning

/// Warnings produced during run recovery. Aggregates trace-level warnings
/// with recovery-specific diagnostics.
public enum RecoveryWarning: Equatable {
    /// A gap was detected in the `seq` sequence.
    case missingSeq(UInt64)
    /// A duplicate `seq` number was detected and skipped.
    case duplicateSeq(UInt64)
    /// A trace line could not be decoded.
    case corruptLine(Int, Error)
    /// The run trace has no terminal event (completed/failed/cancelled).
    case incompleteRun(String)
    /// An event used a schema version newer than the reader supports.
    case futureVersion(Int)

    public static func == (lhs: RecoveryWarning, rhs: RecoveryWarning) -> Bool {
        switch (lhs, rhs) {
        case let (.missingSeq(a), .missingSeq(b)):
            return a == b
        case let (.duplicateSeq(a), .duplicateSeq(b)):
            return a == b
        case let (.corruptLine(a, _), .corruptLine(b, _)):
            return a == b
        case let (.incompleteRun(a), .incompleteRun(b)):
            return a == b
        case let (.futureVersion(a), .futureVersion(b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Recovered Run

/// The complete result of recovering a run from its trace file.
///
/// Bundles the run metadata, raw events, rebuilt snapshot, and timeline
/// so callers get everything in one pass without re-reading the trace.
public struct RecoveredRun {
    /// The recovered run metadata. If the trace has a `runStarted` event,
    /// the run is reconstructed from it; otherwise a minimal stub is created.
    public let run: AgentRun

    /// The raw events from the trace, sorted by `seq` and filtered
    /// (duplicates removed, corrupt lines skipped).
    public let events: [RuntimeEvent]

    /// The session snapshot rebuilt by replaying events through the reducer.
    public let snapshot: SessionSnapshot

    /// The timeline items built from the event stream.
    public let timeline: [TimelineItem]

    /// Non-fatal warnings encountered during recovery.
    public let warnings: [RecoveryWarning]
}

// MARK: - RunRecoveryService

/// Recovers a complete `AgentRun` from its persisted trace file.
///
/// This is the primary entry point for crash recovery, history browsing,
/// and offline analysis. It reads the trace, replays it through the
/// reducer and timeline builder, and returns a `RecoveredRun` bundle.
///
/// Design goals:
/// - **Deterministic**: same trace always produces identical output
/// - **Resilient**: corrupt lines are skipped with warnings, never thrown
/// - **Complete**: bundles run, events, snapshot, and timeline in one pass
public struct RunRecoveryService {
    private let baseDirectory: URL

    /// Create a recovery service that reads traces from the given base directory.
    ///
    /// The default path is `.macrelay/sessions/` relative to the current directory,
    /// matching TraceWriter's default output.
    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".macrelay/sessions")
    }

    // MARK: - Public API

    /// Recover a run from its trace file.
    ///
    /// - Parameter runID: The run identifier to recover.
    /// - Returns: A `RecoveredRun` bundle with the run, events, snapshot, timeline, and warnings.
    /// - Throws: `RecoveryError.traceNotFound` if no trace file exists for the run.
    public func recover(runID: String) throws -> RecoveredRun {
        let reader = TraceReader(runID: runID, baseDirectory: baseDirectory)
        guard reader.exists else {
            throw RecoveryError.traceNotFound(runID: runID)
        }

        let readResult = reader.readAll()

        // Convert trace warnings to recovery warnings
        var warnings: [RecoveryWarning] = readResult.warnings.compactMap { warning in
            switch warning {
            case let .missingSeq(seq):
                return .missingSeq(seq)
            case let .duplicateSeq(seq, _):
                return .duplicateSeq(seq)
            case let .corruptLine(line, message):
                return .corruptLine(line, RecoveryError.corruptLine(line, message))
            case let .futureVersion(version, _):
                return .futureVersion(version)
            }
        }

        let events = readResult.events

        guard !events.isEmpty else {
            // Empty trace — return a minimal recovery with a stub run
            let stubRun = AgentRun(
                id: runID,
                sessionID: "",
                runtime: .local,
                status: .failed,
                resultSummary: "Empty trace"
            )
            warnings.append(.incompleteRun("Trace file is empty"))
            return RecoveredRun(
                run: stubRun,
                events: [],
                snapshot: SessionSnapshot(),
                timeline: [],
                warnings: warnings
            )
        }

        // Rebuild snapshot and timeline from events
        let snapshot = SnapshotRebuilder.rebuild(from: events)
        let timeline = TimelineBuilder().build(from: events)

        // Recover the run from events
        let run = recoverRun(from: events, runID: runID, warnings: &warnings)

        return RecoveredRun(
            run: run,
            events: events,
            snapshot: snapshot,
            timeline: timeline,
            warnings: warnings
        )
    }

    // MARK: - Internal

    /// Reconstruct an `AgentRun` from the event stream.
    ///
    /// Walks the events to find run lifecycle events and builds the run object.
    /// If no `runStarted` event exists, creates a stub from available data.
    private func recoverRun(
        from events: [RuntimeEvent],
        runID: String,
        warnings: inout [RecoveryWarning]
    ) -> AgentRun {
        // Look for run lifecycle events
        var runInput: String?
        var runtime: RuntimeIdentifier = .local
        var sessionID: String = ""
        var status: RunStatus = .created
        var startedAt: Date?
        var finishedAt: Date?
        var resultSummary: String?
        var firstTimestamp: Date?
        var lastTimestamp: Date?

        for event in events {
            // Track timestamps for duration calculation
            if firstTimestamp == nil {
                firstTimestamp = event.timestamp
            }
            lastTimestamp = event.timestamp

            // Track session and runtime from any event
            if let sid = event.sessionID, !sid.isEmpty {
                sessionID = sid
            }
            runtime = event.runtime

            switch event.type {
            case .runStarted:
                if case let .runStarted(_, input) = event.payload {
                    runInput = input
                    status = .running
                    startedAt = event.timestamp
                }

            case .runWaitingApproval:
                status = .waitingApproval

            case .runResumed:
                status = .running

            case .runCompleted:
                if case let .runCompleted(_, summary) = event.payload {
                    status = .completed
                    finishedAt = event.timestamp
                    resultSummary = summary
                }

            case .runFailed:
                if case let .runFailed(_, error) = event.payload {
                    status = .failed
                    finishedAt = event.timestamp
                    resultSummary = error
                }

            case .runCancelled:
                status = .cancelled
                finishedAt = event.timestamp

            case .turnStarted:
                // If no runStarted event, infer input from first turn
                if runInput == nil {
                    if case let .turnStarted(_, input) = event.payload {
                        runInput = input
                    }
                    if status == .created {
                        status = .running
                        startedAt = event.timestamp
                    }
                }

            case .exited:
                // App exited — if run wasn't terminal, mark as incomplete
                if !isTerminal(status) {
                    status = .failed
                    finishedAt = event.timestamp
                    resultSummary = "Process exited unexpectedly"
                    warnings.append(.incompleteRun("Process exited while run was \(status.rawValue)"))
                }

            default:
                break
            }
        }

        // If still not terminal, the trace was cut short (crash)
        if !isTerminal(status) {
            warnings.append(.incompleteRun("Run ended in non-terminal state: \(status.rawValue)"))
            // Don't force a terminal state — the caller can decide
        }

        // Build the run object
        var run = AgentRun(
            id: runID,
            sessionID: sessionID,
            runtime: runtime,
            createdAt: firstTimestamp ?? Date(),
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: status,
            input: runInput,
            resultSummary: resultSummary
        )

        // If we inferred a start time but the run wasn't explicitly started
        if startedAt != nil && run.status == .created {
            run.status = .running
        }

        return run
    }

    /// Check if a RunStatus is terminal (completed, failed, or cancelled).
    private func isTerminal(_ status: RunStatus) -> Bool {
        switch status {
        case .completed, .failed, .cancelled:
            return true
        case .created, .running, .waitingApproval:
            return false
        }
    }
}

// MARK: - Recovery Error

public enum RecoveryError: Error, LocalizedError {
    case traceNotFound(runID: String)
    case corruptLine(Int, String)

    public var errorDescription: String? {
        switch self {
        case .traceNotFound(let runID):
            return "No trace file found for runID: \(runID)"
        case .corruptLine(let line, let message):
            return "Corrupt line \(line + 1): \(message)"
        }
    }
}
