import Foundation

// MARK: - SnapshotRebuilder

/// Rebuilds a `SessionSnapshot` from a sequence of `RuntimeEvent`s.
///
/// This is the canonical way to reconstruct state from a trace file:
///
///     let reader = TraceReader(fileURL: traceURL)
///     let result = try reader.readAll()
///     let snapshot = SnapshotRebuilder.rebuild(from: result.events)
///
/// The reducer is stateless — each event is fed through
/// `SessionStateReducer.actions(from: RuntimeEvent)` and the resulting
/// actions are applied to a fresh snapshot.
public enum SnapshotRebuilder {

    /// Rebuild a snapshot from an array of RuntimeEvents.
    ///
    /// Events must be in `seq` order (TraceReader guarantees this).
    /// Unknown event types produce no actions and are silently skipped.
    public static func rebuild(from events: [RuntimeEvent]) -> SessionSnapshot {
        let reducer = SessionStateReducer()
        var snapshot = SessionSnapshot()

        for event in events {
            let actions = reducer.actions(from: event)
            for action in actions {
                reducer.reduce(&snapshot, action: action)
            }
        }

        return snapshot
    }

    /// Rebuild a snapshot and also return the accumulated timeline.
    ///
    /// Useful when you need both the state (for UI) and the timeline
    /// (for display) from the same trace without processing it twice.
    public static func rebuildWithTimeline(
        from events: [RuntimeEvent]
    ) -> (snapshot: SessionSnapshot, timeline: [TimelineItem]) {
        let snapshot = rebuild(from: events)
        let timeline = TimelineBuilder().build(from: events)
        return (snapshot, timeline)
    }
}
