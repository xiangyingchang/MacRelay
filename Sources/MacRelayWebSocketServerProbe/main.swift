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

func connect(to port: UInt16) -> URLSessionWebSocketTask {
    let session = URLSession(configuration: .ephemeral)
    let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/relay")!)
    task.resume()
    return task
}

func readAuthResponse(on task: URLSessionWebSocketTask) throws -> [String: Any] {
    let data = try send(
        RelayEnvelope(type: "mac-relay.authorize", payload: ["token": "wrong-bad-token"] as [String: String]),
        on: task
    )
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    return object
}

func readAuthEnvelope(on task: URLSessionWebSocketTask, token: String, decoder: JSONDecoder) throws -> RelayEnvelope<[String: String]> {
    let data = try send(
        RelayEnvelope(type: "mac-relay.authorize", payload: ["token": token] as [String: String]),
        on: task
    )
    return try decoder.decode(RelayEnvelope<[String: String]>.self, from: data)
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

let correctToken = "test-token-ws-\(UUID().uuidString.prefix(8))"
let server = MacRelayWebSocketServer(relayService: service, pairingToken: correctToken)
try server.start(port: 0)
try expect(server.waitUntilReady(), "server should become ready")
let boundPort = try server.port ?? { throw ProbeError.failed("server should bind a local port") }()

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

// Scenario 1: connection without auth — first non-authorize message returns error
let noAuthTask = connect(to: boundPort)
defer { noAuthTask.cancel(with: .normalClosure, reason: nil) }
let noAuthResponseData = try send(
    RelayEnvelope(type: RelayCommandType.snapshotGet.rawValue, payload: [:] as [String: String]),
    on: noAuthTask
)
let noAuthResponse = try decoder.decode(RelayEnvelope<[String: String]>.self, from: noAuthResponseData)
try expect(noAuthResponse.type == RelayEventType.error.rawValue, "no-auth should return error")
try expect(noAuthResponse.payload["error"]?.contains("authorize") == true, "no-auth error should mention authorize")

// Scenario 2: wrong token via authorize envelope
let badTask = connect(to: boundPort)
defer { badTask.cancel(with: .normalClosure, reason: nil) }
let badAuthResponse = try readAuthResponse(on: badTask)
try expect(badAuthResponse["type"] as? String == RelayEventType.error.rawValue, "wrong token should return error")
try expect(badAuthResponse["payload"] as? [String: String] != nil, "wrong token error should have payload")
try expect((badAuthResponse["payload"] as? [String: String])?["error"] == "invalid pairing token", "wrong token error mismatch")

// Scenario 3: correct token, then normal snapshot/replay/heartbeat
let goodTask = connect(to: boundPort)
defer { goodTask.cancel(with: .normalClosure, reason: nil) }
let authResult = try readAuthEnvelope(on: goodTask, token: correctToken, decoder: decoder)
try expect(authResult.type == "mac-relay.authenticated", "correct token should authenticate")
try expect(authResult.payload["status"] == "ok", "auth success status mismatch")

let snapshotResponseData = try send(
    RelayEnvelope(type: RelayCommandType.snapshotGet.rawValue, payload: [:] as [String: String]),
    on: goodTask
)
let snapshot = try decoder.decode(RelayEnvelope<RelaySnapshotPayload>.self, from: snapshotResponseData)
try expect(snapshot.type == RelayEventType.snapshot.rawValue, "snapshot response type mismatch")
try expect(snapshot.payload.activeSessionID == "thread-ws", "snapshot session mismatch")
try expect(snapshot.payload.session?.assistantText == "hello websocket", "snapshot assistant mismatch")

let replayResponseData = try send(
    RelayEnvelope(type: RelayCommandType.replayFrom.rawValue, payload: RelayReplayRequestPayload(afterSeq: 1, maxEvents: 10)),
    on: goodTask
)
let replay = try decoder.decode(RelayEnvelope<RelayHTTPReplayPayload>.self, from: replayResponseData)
try expect(replay.payload.kind == "events", "replay kind mismatch")
try expect(!replay.payload.events.isEmpty, "replay events empty")
try expect(replay.payload.events.allSatisfy { $0.seq > 1 }, "replay returned stale events")

let heartbeatResponseData = try send(
    RelayEnvelope(type: RelayCommandType.heartbeatPing.rawValue, payload: [:] as [String: String]),
    on: goodTask
)
let heartbeat = try decoder.decode(RelayEnvelope<ConnectionSnapshotPayload>.self, from: heartbeatResponseData)
try expect(heartbeat.type == RelayEventType.heartbeat.rawValue, "heartbeat type mismatch")
try expect(heartbeat.payload.isOnline, "heartbeat should be online")
try expect(heartbeat.payload.lastSeenSeq == service.newestSeq, "heartbeat seq mismatch")

server.stop()

print("MacRelayWebSocketServerProbe passed auth=tested standardWebSocket=true port=\(boundPort) seq=\(service.newestSeq) replayEvents=\(replay.payload.events.count)")
