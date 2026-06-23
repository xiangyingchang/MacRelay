import Foundation

public enum MacRelayCommandResult {
    case snapshot(RelayEnvelope<RelaySnapshotPayload>)
    case replay(EventReplayResult)
    case unsupported(type: String, reason: String)
}

public final class MacRelayService {
    public private(set) var snapshot = SessionSnapshot()

    private let reducer = SessionStateReducer()
    private let sequence: RelaySequence
    private let store: EventStore
    private let connection: ConnectionSnapshotPayload

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
        return RelaySnapshotPayload(
            activeSessionID: snapshot.threadID,
            session: RelaySessionSnapshotPayload(snapshot: snapshot),
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
        #if os(macOS)
        case .exited:
            type = .error
        #endif
        case .rateLimitsUpdated:
            type = nil
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
