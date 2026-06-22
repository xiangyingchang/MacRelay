import AgentClientCore
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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

func send<Payload: Encodable>(_ envelope: RelayEnvelope<Payload>, on task: URLSessionWebSocketTask) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(envelope)
    let text = String(data: data, encoding: .utf8) ?? "{}"

    let sendSemaphore = DispatchSemaphore(value: 0)
    var sendError: Error?
    task.send(.string(text)) { error in
        sendError = error
        sendSemaphore.signal()
    }
    _ = sendSemaphore.wait(timeout: .now() + .seconds(10))
    if let sendError { throw sendError }

    let receiveSemaphore = DispatchSemaphore(value: 0)
    var receiveResult: Result<Data, Error>?
    task.receive { result in
        switch result {
        case .success(.data(let data)):
            receiveResult = .success(data)
        case .success(.string(let string)):
            receiveResult = .success(Data(string.utf8))
        case .failure(let error):
            receiveResult = .failure(error)
        @unknown default:
            receiveResult = .failure(ProbeError.failed("unknown websocket message type"))
        }
        receiveSemaphore.signal()
    }
    _ = receiveSemaphore.wait(timeout: .now() + .seconds(10))
    return try receiveResult?.get() ?? Data()
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
try expect(server.waitUntilReady(), "server should become ready")
let boundPort = try server.port ?? { throw ProbeError.failed("server should bind a local port") }()

let session = URLSession(configuration: .ephemeral)
let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(boundPort)/relay")!)
task.resume()

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

let snapshotResponseData = try send(
    RelayEnvelope(type: RelayCommandType.snapshotGet.rawValue, payload: [:] as [String: String]),
    on: task
)
let snapshot = try decoder.decode(RelayEnvelope<RelaySnapshotPayload>.self, from: snapshotResponseData)
try expect(snapshot.type == RelayEventType.snapshot.rawValue, "snapshot response type mismatch")
try expect(snapshot.payload.activeSessionID == "thread-ws", "snapshot session mismatch")
try expect(snapshot.payload.session?.assistantText == "hello websocket", "snapshot assistant mismatch")

let replayResponseData = try send(
    RelayEnvelope(type: RelayCommandType.replayFrom.rawValue, payload: RelayReplayRequestPayload(afterSeq: 1, maxEvents: 10)),
    on: task
)
let replay = try decoder.decode(RelayEnvelope<RelayHTTPReplayPayload>.self, from: replayResponseData)
try expect(replay.payload.kind == "events", "replay kind mismatch")
try expect(!replay.payload.events.isEmpty, "replay events empty")
try expect(replay.payload.events.allSatisfy { $0.seq > 1 }, "replay returned stale events")

let heartbeatResponseData = try send(
    RelayEnvelope(type: RelayCommandType.heartbeatPing.rawValue, payload: [:] as [String: String]),
    on: task
)
let heartbeat = try decoder.decode(RelayEnvelope<ConnectionSnapshotPayload>.self, from: heartbeatResponseData)
try expect(heartbeat.type == RelayEventType.heartbeat.rawValue, "heartbeat type mismatch")
try expect(heartbeat.payload.isOnline, "heartbeat should be online")
try expect(heartbeat.payload.lastSeenSeq == service.newestSeq, "heartbeat seq mismatch")

task.cancel(with: .normalClosure, reason: nil)
server.stop()

print("MacRelayWebSocketServerProbe passed standardWebSocket=true port=\(boundPort) seq=\(service.newestSeq) replayEvents=\(replay.payload.events.count)")
