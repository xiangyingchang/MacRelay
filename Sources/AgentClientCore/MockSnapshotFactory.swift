import Foundation

public enum MockSnapshotFactory {
    public static func makeRelaySnapshot(
        deviceID: String = "local-mock",
        macName: String? = Host.current().localizedName
    ) -> RelaySnapshotPayload {
        let reducer = SessionStateReducer()
        var snapshot = SessionSnapshot()
        let sequence = RelaySequence()
        let store = EventStore(capacity: 100)

        func record<Payload: Codable>(type: RelayEventType, payload: Payload) throws {
            let envelope = sequence.assign(RelayEnvelope(type: type.rawValue, payload: payload))
            try store.append(StoredRelayEvent(envelope: envelope))
        }

        func apply(_ event: CodexAppServerEvent) throws {
            for action in reducer.actions(from: event) {
                reducer.reduce(&snapshot, action: action)
                switch action {
                case .threadStarted:
                    try record(type: .sessionStarted, payload: RelaySessionSnapshotPayload(snapshot: snapshot))
                case .statusChanged:
                    try record(type: .sessionStatusChanged, payload: RelaySessionSnapshotPayload(snapshot: snapshot))
                case .settingsUpdated:
                    try record(type: .sessionSettingsUpdated, payload: RelaySessionSnapshotPayload(snapshot: snapshot))
                case .turnStarted:
                    try record(type: .turnStarted, payload: RelaySessionSnapshotPayload(snapshot: snapshot))
                case .assistantDelta:
                    try record(type: .turnDelta, payload: RelaySessionSnapshotPayload(snapshot: snapshot))
                case .turnCompleted:
                    try record(type: .turnCompleted, payload: RelaySessionSnapshotPayload(snapshot: snapshot))
                case .approvalRequested:
                    try record(type: .approvalRequested, payload: RelaySnapshotPayload(
                        activeSessionID: snapshot.threadID,
                        session: RelaySessionSnapshotPayload(snapshot: snapshot),
                        connection: ConnectionSnapshotPayload(isPaired: true, isOnline: true, lastSeenSeq: store.newestSeq),
                        pendingApprovals: snapshot.pendingApprovals.values.map(RelayApprovalPayload.init),
                        lastEventSeq: store.newestSeq ?? 0
                    ))
                case .diffUpdated:
                    try record(type: .diffUpdated, payload: RelaySessionSnapshotPayload(snapshot: snapshot))
                case .fileChangeUpdated:
                    try record(type: .fileChangeUpdated, payload: RelaySessionSnapshotPayload(snapshot: snapshot))
                case .error:
                    try record(type: .error, payload: RelaySessionSnapshotPayload(snapshot: snapshot))
                case .rateLimitsUpdated, .approvalResolved, .exited:
                    break
                }
            }
        }

        do {
            try apply(.notification(method: "thread/started", params: [
                "thread": ["id": "mock-thread", "cwd": "/tmp/mock-project"]
            ]))
            try apply(.notification(method: "thread/settings/updated", params: [
                "threadSettings": ["model": "gpt-5.5", "effort": "low", "cwd": "/tmp/mock-project"]
            ]))
            try apply(.notification(method: "turn/started", params: [
                "turn": ["id": "mock-turn"]
            ]))
            try apply(.notification(method: "item/agentMessage/delta", params: [
                "delta": "AgentClient Mac mock ready."
            ]))
            try apply(.notification(method: "turn/diff/updated", params: [
                "threadId": "mock-thread",
                "turnId": "mock-turn",
                "diff": "diff --git a/Sources/App.swift b/Sources/App.swift\n--- a/Sources/App.swift\n+++ b/Sources/App.swift\n@@ -1 +1 @@\n-old\n+new\n"
            ]))
            try apply(.notification(method: "item/completed", params: [
                "threadId": "mock-thread",
                "turnId": "mock-turn",
                "item": [
                    "id": "mock-file-change",
                    "type": "fileChange",
                    "path": "Sources/App.swift",
                    "changeKind": "modified",
                    "diff": "diff --git a/Sources/App.swift b/Sources/App.swift\n"
                ]
            ]))
            try apply(.serverRequest(id: 0, method: "item/commandExecution/requestApproval", params: [
                "threadId": "mock-thread",
                "turnId": "mock-turn",
                "itemId": "mock-approval",
                "command": "/bin/zsh -lc swift build",
                "reason": "Run build to verify the generated Swift prototype."
            ]))
            try apply(.notification(method: "turn/completed", params: [
                "threadId": "mock-thread",
                "turn": ["id": "mock-turn", "status": "completed"]
            ]))
        } catch {
            assertionFailure("Mock snapshot generation failed: \(error)")
        }

        return RelaySnapshotPayload(
            activeSessionID: snapshot.threadID,
            session: RelaySessionSnapshotPayload(snapshot: snapshot),
            connection: ConnectionSnapshotPayload(
                deviceID: deviceID,
                macName: macName,
                isPaired: true,
                isOnline: true,
                lastSeenSeq: store.newestSeq
            ),
            pendingApprovals: snapshot.pendingApprovals.values.map(RelayApprovalPayload.init),
            lastEventSeq: store.newestSeq ?? 0
        )
    }
}
