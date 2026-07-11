import Foundation

public enum MacRelayCommandResult {
    case snapshot(RelayEnvelope<RelaySnapshotPayload>)
    case replay(EventReplayResult)
    case unsupported(type: String, reason: String)
}

public final class MacRelayService {
    public private(set) var snapshot = SessionSnapshot()

    /// Unified RuntimeEvent log — the canonical event stream for Trace/Timeline.
    /// Unlike StoredRelayEvent (which embeds full snapshots), RuntimeEvent
    /// carries only the event data. Snapshot can be reconstructed by replaying
    /// RuntimeEvents through the reducer.
    public private(set) var runtimeEvents: [RuntimeEvent] = []
    private let runtimeEventCapacity = 1000

    /// Optional trace writer — when set, every RuntimeEvent is persisted to disk.
    public var traceWriter: TraceStore?

    /// UI settings injected by the view model for snapshot broadcasts.
    /// These are not part of the agent runtime state but need to sync to iOS.
    public var planMode: Bool?
    public var permissionMode: String?
    public var model: String?
    public var effort: String?
    public var provider: String?

    /// Update snapshot settings from the Mac view model so iOS receives current config.
    public func updateSnapshotSettings(
        model: String?,
        effort: String?,
        provider: String?,
        approvalPolicy: String?,
        sandboxType: String?,
        cwd: String?
    ) {
        snapshot.settings = SessionSettingsSnapshot(
            model: model,
            effort: effort,
            provider: provider,
            approvalPolicy: approvalPolicy,
            sandboxType: sandboxType,
            cwd: cwd
        )
    }

    /// Update the available models list on the snapshot.
    public func updateSnapshotAvailableModels(_ models: [String]?) {
        snapshot.availableModels = models
    }

    private let reducer = SessionStateReducer()
    private let sequence: RelaySequence
    private let store: EventStore
    private let connection: ConnectionSnapshotPayload

    /// Dedicated monotonic counter for RuntimeEvent seq values.
    /// Separate from the EventStore's seq (used by StoredRelayEvents) because
    /// RuntimeEvents are persisted to the trace file, not the EventStore.
    /// Using a dedicated counter ensures trace events always have strictly
    /// increasing seqs, even when the deprecated ingest path produces no
    /// StoredRelayEvent (and thus doesn't advance the store's newestSeq).
    private var runtimeEventSeq: UInt64 = 0

    public init(
        eventCapacity: Int = 1000,
        connection: ConnectionSnapshotPayload = ConnectionSnapshotPayload(isPaired: true, isOnline: true),
        sequence: RelaySequence = RelaySequence()
    ) {
        self.store = EventStore(capacity: eventCapacity)
        self.connection = connection
        self.sequence = sequence
    }

    public var newestSeq: UInt64 {
        store.newestSeq ?? 0
    }

    public var eventCount: Int {
        store.count
    }

    public func reset() {
        snapshot = SessionSnapshot()
    }

    // MARK: - Timeline Query

    /// Returns the timeline for the current session or a specific run.
    ///
    /// When `runID` is nil, returns the timeline for all events in the
    /// current session. When provided, filters to only that run's events.
    ///
    /// This is the canonical entry point for UI consumers — they should
    /// never access `runtimeEvents` directly.
    public func timeline(runID: String? = nil) -> [TimelineItem] {
        let filtered: [RuntimeEvent]
        if let runID {
            filtered = runtimeEvents.filter { $0.runID == runID }
        } else {
            filtered = runtimeEvents
        }
        return TimelineBuilder().build(from: filtered)
    }

    /// Returns the timeline for a historical run by reading its trace file.
    ///
    /// Use this when the run is no longer in the in-memory `runtimeEvents`
    /// buffer (e.g. browsing past sessions). The trace is read from disk
    /// via `TraceReader` and converted to timeline items via `TimelineBuilder`.
    ///
    /// - Parameters:
    ///   - runID: The run identifier to recover.
    ///   - baseDirectory: The base directory for trace files. Defaults to
    ///     `.macrelay/sessions/` in the current directory.
    /// - Returns: The timeline items for the historical run, or `nil` if
    ///   the trace file does not exist.
    public func timelineFromTrace(
        runID: String,
        baseDirectory: URL? = nil
    ) -> [TimelineItem]? {
        let base = baseDirectory
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".macrelay/sessions")
        let reader = TraceReader(runID: runID, baseDirectory: base)
        guard reader.exists else { return nil }
        guard let result = try? reader.readAll() else { return nil }
        guard !result.events.isEmpty else { return [] }
        return TimelineBuilder().build(from: result.events)
    }

    /// Returns the timeline for a run, preferring in-memory events and
    /// falling back to the persisted trace file.
    ///
    /// This is the recommended entry point for UI consumers that need to
    /// display timelines for both active and historical runs.
    ///
    /// - Parameters:
    ///   - runID: The run identifier.
    ///   - baseDirectory: The base directory for trace files (used only
    ///     when falling back to disk).
    /// - Returns: The timeline items, or an empty array if no data exists.
    public func timelineWithFallback(
        runID: String,
        baseDirectory: URL? = nil
    ) -> [TimelineItem] {
        // Prefer in-memory events (real-time or recently active)
        let inMemory = runtimeEvents.filter { $0.runID == runID }
        if !inMemory.isEmpty {
            return TimelineBuilder().build(from: inMemory)
        }
        // Fall back to persisted trace
        return timelineFromTrace(runID: runID, baseDirectory: baseDirectory) ?? []
    }

    @discardableResult
    public func ingest(_ event: CodexAppServerEvent) throws -> [StoredRelayEvent] {
        let actions = reducer.actions(from: event)
        guard !actions.isEmpty else { return [] }

        var emitted: [StoredRelayEvent] = []
        for action in actions {
            reducer.reduce(&snapshot, action: action)
            if let stored = try record(action: action) {
                emitted.append(stored)
            }
        }
        return emitted
    }

    /// Adapter for converting Codex events to RuntimeEvents.
    private let codexAdapter = CodexRuntimeAdapter()

    /// Ingest a raw event and also produce unified RuntimeEvents via the adapter.
    /// The RuntimeEvents are stored in `runtimeEvents` for Trace/Timeline use.
    /// Returns (storedRelayEvents, runtimeEvents).
    public func ingestWithRuntimeEvent(
        _ event: CodexAppServerEvent,
        runtime: RuntimeIdentifier,
        sessionID: String? = nil,
        runID: String? = nil
    ) throws -> ([StoredRelayEvent], [RuntimeEvent]) {
        let relayEvents = try ingest(event)

        let adapted = codexAdapter.adapt(event, sessionID: sessionID, runID: runID)
        var result: [RuntimeEvent] = []
        for var evt in adapted {
            runtimeEventSeq += 1
            evt = evt.withSeq(runtimeEventSeq)
            runtimeEvents.append(evt)
            if runtimeEvents.count > runtimeEventCapacity {
                runtimeEvents.removeFirst(runtimeEvents.count - runtimeEventCapacity)
            }
            // Persist to trace file (non-blocking, fire-and-forget)
            try? traceWriter?.append(evt)
            result.append(evt)
        }

        return (relayEvents, result)
    }

    /// Ingest a RuntimeEvent directly — runs it through the reducer and records
    /// each resulting action as a StoredRelayEvent. Used for replay and testing.
    ///
    /// Note: RuntimeEvents are always stored in `runtimeEvents` for Trace/Timeline,
    /// even if they don't produce reducer actions (e.g., tool call events are
    /// "Timeline-only" and don't mutate the snapshot).
    @discardableResult
    public func ingestRuntimeEvent(_ event: RuntimeEvent) throws -> [StoredRelayEvent] {
        // Always store in runtimeEvents for Trace/Timeline
        runtimeEventSeq += 1
        let seqd = event.withSeq(runtimeEventSeq)
        runtimeEvents.append(seqd)
        if runtimeEvents.count > runtimeEventCapacity {
            runtimeEvents.removeFirst(runtimeEvents.count - runtimeEventCapacity)
        }
        try? traceWriter?.append(seqd)

        // Run through reducer for snapshot mutation
        let actions = reducer.actions(from: event)
        guard !actions.isEmpty else { return [] }

        var emitted: [StoredRelayEvent] = []
        for action in actions {
            reducer.reduce(&snapshot, action: action)
            if let stored = try record(action: action) {
                emitted.append(stored)
            }
        }
        return emitted
    }

    public func snapshotEnvelope(correlationID: String? = nil) -> RelayEnvelope<RelaySnapshotPayload> {
        RelayEnvelope(
            type: RelayEventType.snapshot.rawValue,
            seq: newestSeq,
            correlationID: correlationID,
            payload: snapshotPayload()
        )
    }

    public func replay(afterSeq: UInt64, maxEvents: Int? = nil) -> EventReplayResult {
        store.replay(afterSeq: afterSeq, maxEvents: maxEvents)
    }

    public func dispatch(
        commandType: RelayCommandType,
        replayRequest: RelayReplayRequestPayload? = nil,
        correlationID: String? = nil
    ) -> MacRelayCommandResult {
        switch commandType {
        case .snapshotGet:
            return .snapshot(snapshotEnvelope(correlationID: correlationID))
        case .replayFrom:
            guard let replayRequest else {
                return .unsupported(type: commandType.rawValue, reason: "replay.from requires RelayReplayRequestPayload")
            }
            return .replay(replay(afterSeq: replayRequest.afterSeq, maxEvents: replayRequest.maxEvents))
        default:
            return .unsupported(type: commandType.rawValue, reason: "command dispatch not implemented in MacRelayService skeleton")
        }
    }

    private func snapshotPayload() -> RelaySnapshotPayload {
        var connection = connection
        connection.lastSeenSeq = newestSeq
        var session = RelaySessionSnapshotPayload(snapshot: snapshot)
        // Inject UI settings that are not in the agent runtime snapshot
        session.planMode = planMode
        session.permissionMode = permissionMode
        session.provider = provider
        if let model { session.model = model }
        if let effort { session.effort = effort }
        return RelaySnapshotPayload(
            activeSessionID: snapshot.threadID,
            session: session,
            connection: connection,
            pendingApprovals: snapshot.pendingApprovals.values.map(RelayApprovalPayload.init),
            lastEventSeq: newestSeq
        )
    }

    private func record(action: SessionReducerAction) throws -> StoredRelayEvent? {
        let type: RelayEventType?
        switch action {
        case .threadStarted:
            type = .sessionStarted
        case .statusChanged:
            type = .sessionStatusChanged
        case .settingsUpdated:
            type = .sessionSettingsUpdated
        case .turnStarted:
            type = .turnStarted
        case .assistantDelta:
            type = .turnDelta
        case .turnCompleted:
            type = .turnCompleted
        case .approvalRequested:
            type = .approvalRequested
        case .approvalResolved:
            type = .approvalResolved
        case .diffUpdated:
            type = .diffUpdated
        case .fileChangeUpdated:
            type = .fileChangeUpdated
        case .error:
            type = .error
        case .exited:
            type = .error
        case .rateLimitsUpdated:
            type = nil
        case .modelListResult:
            type = nil
        case .runStarted:
            type = .runStarted
        case .runWaitingApproval:
            type = .runWaitingApproval
        case .runResumed:
            type = .runResumed
        case .runCompleted:
            type = .runCompleted
        case .runFailed:
            type = .runFailed
        case .runCancelled:
            type = .runCancelled
        }

        guard let type else { return nil }
        let envelope = sequence.assign(RelayEnvelope(
            type: type.rawValue,
            payload: snapshotPayload()
        ))
        let stored = try StoredRelayEvent(envelope: envelope)
        store.append(stored)
        return stored
    }
}
