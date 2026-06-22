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

func send<Payload: Encodable>(_ envelope: RelayEnvelope<Payload>, to server: MacRelayWebSocketServer) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(envelope)
    let response = server.handleMessage(data)
    if response.isEmpty {
        throw ProbeError.failed("empty relay response")
    }
    return response
}

let service = MacRelayService(eventCapacity: 20)
try ingest(service, .notification(method: "thread/started", params: [
    "thread": ["id": "thread-ws", "cwd": "/tmp/project"]
]))
try ingest(service, .notification(method: "turn/started", params: [
    "turn": ["id": "turn-ws"]
]))
try ingest(service, .notification(method: "item/agentMessage/delta", params: [
    "delta": "hello websocket"
]))
try ingest(service, .notification(method: "turn/completed", params: [
    "threadId": "thread-ws",
    "turn": ["id": "turn-ws", "status": "completed"]
]))

let server = MacRelayWebSocketServer(relayService: service)
try server.start(port: 0)
Thread.sleep(forTimeInterval: 0.15)
try expect(server.port != nil, "server should bind a local port")

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

let snapshotResponseData = try send(
    RelayEnvelope(type: RelayCommandType.snapshotGet.rawValue, payload: [:] as [String: String]),
    to: server
)
let snapshot = try decoder.decode(RelayEnvelope<RelaySnapshotPayload>.self, from: snapshotResponseData)
try expect(snapshot.type == RelayEventType.snapshot.rawValue, "snapshot response type mismatch")
try expect(snapshot.payload.activeSessionID == "thread-ws", "snapshot session mismatch")
try expect(snapshot.payload.session?.assistantText == "hello websocket", "snapshot assistant mismatch")

let replayResponseData = try send(
    RelayEnvelope(type: RelayCommandType.replayFrom.rawValue, payload: RelayReplayRequestPayload(afterSeq: 1, maxEvents: 10)),
    to: server
)
let replay = try decoder.decode(RelayEnvelope<RelayHTTPReplayPayload>.self, from: replayResponseData)
try expect(replay.payload.kind == "events", "replay kind mismatch")
try expect(!replay.payload.events.isEmpty, "replay events empty")
try expect(replay.payload.events.allSatisfy { $0.seq > 1 }, "replay returned stale events")

let heartbeatResponseData = try send(
    RelayEnvelope(type: RelayCommandType.heartbeatPing.rawValue, payload: [:] as [String: String]),
    to: server
)
let heartbeat = try decoder.decode(RelayEnvelope<ConnectionSnapshotPayload>.self, from: heartbeatResponseData)
try expect(heartbeat.type == RelayEventType.heartbeat.rawValue, "heartbeat type mismatch")
try expect(heartbeat.payload.isOnline, "heartbeat should be online")
try expect(heartbeat.payload.lastSeenSeq == service.newestSeq, "heartbeat seq mismatch")

let boundPort = server.port ?? 0
server.stop()

print("MacRelayWebSocketServerProbe passed port=\(boundPort) seq=\(service.newestSeq) replayEvents=\(replay.payload.events.count)")
