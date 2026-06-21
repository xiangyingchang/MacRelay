import AgentClientCore
import Foundation

func log(_ name: String, _ value: Any) {
    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print("[\(name)] \(text)")
    } else {
        print("[\(name)] \(value)")
    }
}

struct RelayTextPayload: Codable {
    var text: String
}

struct RelayStatusPayload: Codable {
    var status: String
}

struct RelayDiffPayload: Codable {
    var changedFiles: [String]
}

let reducer = SessionStateReducer()
var snapshot = SessionSnapshot()
let sequence = RelaySequence()
let store = EventStore(capacity: 10)

func record<Payload: Codable>(type: String, payload: Payload) throws {
    let envelope = sequence.assign(RelayEnvelope(type: type, payload: payload))
    try store.append(StoredRelayEvent(envelope: envelope))
}

func apply(_ event: CodexAppServerEvent) throws {
    for action in reducer.actions(from: event) {
        reducer.reduce(&snapshot, action: action)

        switch action {
        case .threadStarted:
            try record(
                type: RelayEventType.sessionStarted.rawValue,
                payload: RelayStatusPayload(status: snapshot.status.rawValue)
            )
        case .statusChanged:
            try record(
                type: RelayEventType.sessionStatusChanged.rawValue,
                payload: RelayStatusPayload(status: snapshot.status.rawValue)
            )
        case .settingsUpdated:
            try record(
                type: RelayEventType.sessionSettingsUpdated.rawValue,
                payload: RelaySessionSnapshotPayload(snapshot: snapshot)
            )
        case .turnStarted:
            try record(
                type: RelayEventType.turnStarted.rawValue,
                payload: RelayStatusPayload(status: snapshot.status.rawValue)
            )
        case .assistantDelta:
            try record(
                type: RelayEventType.turnDelta.rawValue,
                payload: RelayTextPayload(text: snapshot.activeTurn?.assistantText ?? "")
            )
        case .turnCompleted:
            try record(
                type: RelayEventType.turnCompleted.rawValue,
                payload: RelayStatusPayload(status: snapshot.status.rawValue)
            )
        case .approvalRequested:
            try record(
                type: RelayEventType.approvalRequested.rawValue,
                payload: RelaySnapshotPayload(
                    activeSessionID: snapshot.threadID,
                    session: RelaySessionSnapshotPayload(snapshot: snapshot),
                    connection: ConnectionSnapshotPayload(isPaired: true, isOnline: true, lastSeenSeq: store.newestSeq),
                    pendingApprovals: snapshot.pendingApprovals.values.map(RelayApprovalPayload.init),
                    lastEventSeq: store.newestSeq ?? 0
                )
            )
        case .diffUpdated:
            try record(
                type: RelayEventType.diffUpdated.rawValue,
                payload: RelayDiffPayload(changedFiles: snapshot.turnDiff?.changedFiles ?? [])
            )
        case .fileChangeUpdated:
            try record(
                type: RelayEventType.fileChangeUpdated.rawValue,
                payload: RelaySessionSnapshotPayload(snapshot: snapshot)
            )
        case .error:
            try record(
                type: RelayEventType.error.rawValue,
                payload: RelaySessionSnapshotPayload(snapshot: snapshot)
            )
        case .rateLimitsUpdated, .exited, .approvalResolved:
            break
        }
    }
}

try apply(.notification(method: "thread/started", params: [
    "thread": ["id": "thread-core", "cwd": "/tmp/project"]
]))
try apply(.notification(method: "thread/settings/updated", params: [
    "threadSettings": ["model": "gpt-5.5", "effort": "low", "cwd": "/tmp/project"]
]))
try apply(.notification(method: "turn/started", params: [
    "turn": ["id": "turn-core"]
]))
try apply(.notification(method: "item/agentMessage/delta", params: [
    "delta": "hello"
]))
try apply(.notification(method: "item/agentMessage/delta", params: [
    "delta": " relay"
]))
try apply(.serverRequest(id: 0, method: "item/commandExecution/requestApproval", params: [
    "threadId": "thread-core",
    "turnId": "turn-core",
    "itemId": "approval-core",
    "command": "/bin/zsh -lc touch file.txt",
    "reason": "Need to create file"
]))
try apply(.notification(method: "turn/diff/updated", params: [
    "threadId": "thread-core",
    "turnId": "turn-core",
    "diff": "diff --git a/file.txt b/file.txt\n--- a/file.txt\n+++ b/file.txt\n@@ -0,0 +1 @@\n+hello\n"
]))
try apply(.notification(method: "item/completed", params: [
    "threadId": "thread-core",
    "turnId": "turn-core",
    "item": [
        "id": "file-change-core",
        "type": "fileChange",
        "path": "file.txt",
        "changeKind": "modified",
        "diff": "diff --git a/file.txt b/file.txt\n"
    ]
]))
try apply(.notification(method: "turn/completed", params: [
    "threadId": "thread-core",
    "turn": ["id": "turn-core", "status": "completed"]
]))

let fullSnapshot = RelaySnapshotPayload(
    activeSessionID: snapshot.threadID,
    session: RelaySessionSnapshotPayload(snapshot: snapshot),
    connection: ConnectionSnapshotPayload(
        deviceID: "iphone-core",
        macName: "Fixture Mac",
        isPaired: true,
        isOnline: true,
        lastSeenSeq: store.newestSeq
    ),
    pendingApprovals: snapshot.pendingApprovals.values.map(RelayApprovalPayload.init),
    lastEventSeq: store.newestSeq ?? 0
)

let snapshotEnvelope = sequence.assign(RelayEnvelope(
    type: RelayEventType.snapshot.rawValue,
    payload: fullSnapshot
))

let snapshotData = try JSONEncoder().encode(snapshotEnvelope)
let decodedSnapshot = try JSONDecoder().decode(RelayEnvelope<RelaySnapshotPayload>.self, from: snapshotData)

func describeReplay(_ result: EventReplayResult) -> Any {
    switch result {
    case let .events(events):
        return [
            "kind": "events",
            "seqs": events.map(\.seq),
            "types": events.map(\.type)
        ]
    case let .needsFullSnapshot(reason):
        return [
            "kind": "needsFullSnapshot",
            "reason": reason
        ]
    }
}

log("relayCore.snapshot", [
    "type": decodedSnapshot.type,
    "lastEventSeq": decodedSnapshot.payload.lastEventSeq,
    "status": decodedSnapshot.payload.session?.status as Any,
    "assistantText": decodedSnapshot.payload.session?.assistantText as Any,
    "changedFiles": decodedSnapshot.payload.session?.changedFiles as Any,
    "pendingApprovals": decodedSnapshot.payload.pendingApprovals.count
])

log("relayCore.store", [
    "count": store.count,
    "oldestSeq": store.oldestSeq as Any,
    "newestSeq": store.newestSeq as Any
])

log("relayCore.replay.after3", describeReplay(store.replay(afterSeq: 3)))
log("relayCore.replay.afterNewest", describeReplay(store.replay(afterSeq: store.newestSeq ?? 0)))
