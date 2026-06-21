import AgentClientCore
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw ProbeError.failed(message)
    }
}

func ingest(_ service: MacRelayService, _ event: CodexAppServerEvent) throws {
    _ = try service.ingest(event)
}

let service = MacRelayService(
    eventCapacity: 20,
    connection: ConnectionSnapshotPayload(
        deviceID: "iphone-fixture",
        macName: "Fixture Mac",
        isPaired: true,
        isOnline: true
    )
)

try ingest(service, .notification(method: "thread/started", params: [
    "thread": ["id": "thread-relay", "cwd": "/tmp/project"]
]))
try ingest(service, .notification(method: "thread/settings/updated", params: [
    "threadSettings": [
        "model": "gpt-5.5",
        "effort": "low",
        "approvalPolicy": "on-request",
        "sandboxPolicy": ["type": "readOnly"],
        "cwd": "/tmp/project"
    ]
]))
try ingest(service, .notification(method: "turn/started", params: [
    "turn": ["id": "turn-relay"]
]))
try ingest(service, .notification(method: "item/agentMessage/delta", params: [
    "delta": "hello"
]))
try ingest(service, .notification(method: "item/agentMessage/delta", params: [
    "delta": " relay"
]))
try ingest(service, .serverRequest(id: 7, method: "item/commandExecution/requestApproval", params: [
    "threadId": "thread-relay",
    "turnId": "turn-relay",
    "itemId": "approval-relay",
    "command": "/bin/zsh -lc touch file.txt",
    "reason": "Need to create file"
]))
try ingest(service, .notification(method: "turn/diff/updated", params: [
    "threadId": "thread-relay",
    "turnId": "turn-relay",
    "diff": "diff --git a/file.txt b/file.txt\n--- a/file.txt\n+++ b/file.txt\n@@ -0,0 +1 @@\n+hello\n"
]))
try ingest(service, .notification(method: "item/completed", params: [
    "threadId": "thread-relay",
    "turnId": "turn-relay",
    "item": [
        "id": "file-change-relay",
        "type": "fileChange",
        "path": "file.txt",
        "changeKind": "modified",
        "diff": "diff --git a/file.txt b/file.txt\n"
    ]
]))
try ingest(service, .notification(method: "turn/completed", params: [
    "threadId": "thread-relay",
    "turn": ["id": "turn-relay", "status": "completed"]
]))

let snapshot = service.snapshotEnvelope(correlationID: "snapshot-command")
try expect(snapshot.type == RelayEventType.snapshot.rawValue, "snapshot envelope type mismatch")
try expect(snapshot.correlationID == "snapshot-command", "snapshot correlationID mismatch")
try expect(snapshot.payload.activeSessionID == "thread-relay", "activeSessionID mismatch")
try expect(snapshot.payload.session?.assistantText == "hello relay", "assistant text mismatch")
try expect(snapshot.payload.session?.changedFiles == ["file.txt"], "changed files mismatch")
try expect(snapshot.payload.pendingApprovals.count == 1, "pending approval count mismatch")
try expect(snapshot.payload.lastEventSeq == service.newestSeq, "snapshot seq mismatch")
try expect(service.eventCount >= 8, "expected relay events to be stored")

switch service.replay(afterSeq: 3) {
case let .events(events):
    try expect(!events.isEmpty, "replay after seq 3 should return events")
    try expect(events.allSatisfy { $0.seq > 3 }, "replay returned stale seq")
case let .needsFullSnapshot(reason):
    throw ProbeError.failed("unexpected needsFullSnapshot: \(reason)")
}

switch service.dispatch(commandType: .snapshotGet, correlationID: "cmd-1") {
case let .snapshot(envelope):
    try expect(envelope.correlationID == "cmd-1", "dispatch snapshot correlation mismatch")
    try expect(envelope.payload.session?.status == "completed", "dispatch snapshot status mismatch")
default:
    throw ProbeError.failed("snapshot.get did not return snapshot")
}

switch service.dispatch(
    commandType: .replayFrom,
    replayRequest: RelayReplayRequestPayload(afterSeq: service.newestSeq, maxEvents: 10)
) {
case let .replay(.events(events)):
    try expect(events.isEmpty, "replay after newest should be empty")
default:
    throw ProbeError.failed("replay.from did not return empty replay")
}

switch service.dispatch(commandType: .turnStart) {
case let .unsupported(type, _):
    try expect(type == RelayCommandType.turnStart.rawValue, "unsupported type mismatch")
default:
    throw ProbeError.failed("turnStart should be unsupported in skeleton")
}

print("MacRelayServiceFixtureProbe passed seq=\(service.newestSeq) events=\(service.eventCount)")
