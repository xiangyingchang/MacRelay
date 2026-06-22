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
try expect((badAuthResponse["payload"] as? [String: String])?["error"]?.contains("invalid") == true, "wrong token error mismatch")

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

// Scenario 4: device credential auth
let trustStore = MemoryDeviceTrustStore()
let deviceID = "iphone-sim-1"
let deviceSecret = "dev-secret-xyz"
try trustStore.register(DeviceIdentity(deviceID: deviceID, deviceSecret: deviceSecret, deviceName: "Simulator"))

let deviceServer = MacRelayWebSocketServer(relayService: service,
                                          pairingToken: "ignored-token",
                                          deviceTrustStore: trustStore)
try deviceServer.start(port: 0)
try expect(deviceServer.waitUntilReady(), "deviceServer should become ready")
let devicePort = try deviceServer.port ?? { throw ProbeError.failed("deviceServer port") }()

let deviceTask = connect(to: devicePort)
defer { deviceTask.cancel(with: .normalClosure, reason: nil) }

// Wrong device secret -> rejected
let wrongDeviceAuth = try readAuthResponse(on: deviceTask)
try expect(wrongDeviceAuth["type"] as? String == RelayEventType.error.rawValue, "wrong device auth error")

// Correct device auth on new task
let deviceTask2 = connect(to: devicePort)
defer { deviceTask2.cancel(with: .normalClosure, reason: nil) }
let deviceAuthData = try send(
    RelayEnvelope(type: "mac-relay.authorize", payload: ["deviceId": deviceID, "deviceSecret": deviceSecret] as [String: String]),
    on: deviceTask2
)
let deviceAuthResult = try decoder.decode(RelayEnvelope<[String: String]>.self, from: deviceAuthData)
try expect(deviceAuthResult.type == "mac-relay.authenticated", "device auth should authenticate")
try expect(deviceAuthResult.payload["method"] == "device-static", "device auth method marker")

let deviceSnapshotData = try send(
    RelayEnvelope(type: RelayCommandType.snapshotGet.rawValue, payload: [:] as [String: String]),
    on: deviceTask2
)
let deviceSnapshot = try decoder.decode(RelayEnvelope<RelaySnapshotPayload>.self, from: deviceSnapshotData)
try expect(deviceSnapshot.payload.activeSessionID == "thread-ws", "device snapshot session")

// Challenge-response device auth
let challengeStore = MemoryDeviceTrustStore()
let challengeDeviceID = "ch-iphone"
let challengeSecret = "ch-secret-abc"
try challengeStore.register(DeviceIdentity(deviceID: challengeDeviceID, deviceSecret: challengeSecret, deviceName: "Challenge iPhone"))

let chServer = MacRelayWebSocketServer(relayService: service,
                                      pairingToken: "ignored",
                                      deviceTrustStore: challengeStore)
try chServer.start(port: 0)
try expect(chServer.waitUntilReady(), "chServer ready")
let chPort = try chServer.port ?? { throw ProbeError.failed("chServer port") }()

// Step 1: connect and request challenge
let chTask = connect(to: chPort)
defer { chTask.cancel(with: .normalClosure, reason: nil) }
let challengeResp = try send(
    RelayEnvelope(type: "mac-relay.authorize", payload: ["deviceId": challengeDeviceID] as [String: String]),
    on: chTask
)
let challengeObj = try JSONSerialization.jsonObject(with: challengeResp) as? [String: Any] ?? [:]
try expect(challengeObj["type"] as? String == "mac-relay.challenge", "should get challenge")
let nonce = challengeObj["payload"] as? [String: Any] ?? [:]
let nonceStr = nonce["nonce"] as? String ?? ""
try expect(!nonceStr.isEmpty, "nonce non-empty")

// Step 2: compute response and authorize
let response = NonceManager.hash(nonceStr, withSecret: challengeSecret)
let authResp = try send(
    RelayEnvelope(type: "mac-relay.authorize", payload: ["deviceId": challengeDeviceID, "challengeResponse": response] as [String: String]),
    on: chTask
)
let authEnv = try decoder.decode(RelayEnvelope<[String: String]>.self, from: authResp)
try expect(authEnv.type == "mac-relay.authenticated", "challenge auth ok")
try expect(authEnv.payload["method"] == "device-challenge", "device-challenge method")

// Step 3: wrong response is rejected
let wrongTask = connect(to: chPort)
defer { wrongTask.cancel(with: .normalClosure, reason: nil) }
_ = try send(  // get challenge
    RelayEnvelope(type: "mac-relay.authorize", payload: ["deviceId": challengeDeviceID] as [String: String]),
    on: wrongTask
)
let wrongAuth = try send(
    RelayEnvelope(type: "mac-relay.authorize", payload: ["deviceId": challengeDeviceID, "challengeResponse": "bad-response"] as [String: String]),
    on: wrongTask
)
let wrongEnv = try decoder.decode(RelayEnvelope<[String: String]>.self, from: wrongAuth)
try expect(wrongEnv.type == RelayEventType.error.rawValue, "wrong challenge response error")

// Step 4: replay is rejected (same nonce twice)
let replayTask = connect(to: chPort)
defer { replayTask.cancel(with: .normalClosure, reason: nil) }
let replayChallengeResp = try send(
    RelayEnvelope(type: "mac-relay.authorize", payload: ["deviceId": challengeDeviceID] as [String: String]),
    on: replayTask
)
let replayChallengeObj = try JSONSerialization.jsonObject(with: replayChallengeResp) as? [String: Any] ?? [:]
let replayNonce = (replayChallengeObj["payload"] as? [String: Any])?["nonce"] as? String ?? ""
try expect(!replayNonce.isEmpty, "replay nonce")

// First use is ok
let replayAuthOk = try send(
    RelayEnvelope(type: "mac-relay.authorize", payload: ["deviceId": challengeDeviceID, "challengeResponse": NonceManager.hash(replayNonce, withSecret: challengeSecret)] as [String: String]),
    on: replayTask
)
let replayOkEnv = try decoder.decode(RelayEnvelope<[String: String]>.self, from: replayAuthOk)
try expect(replayOkEnv.type == "mac-relay.authenticated", "first use ok")

// Replay same nonce on new connection
let replayTask2 = connect(to: chPort)
defer { replayTask2.cancel(with: .normalClosure, reason: nil) }
let replayAuthBad = try send(
    RelayEnvelope(type: "mac-relay.authorize", payload: ["deviceId": challengeDeviceID, "challengeResponse": NonceManager.hash(replayNonce, withSecret: challengeSecret)] as [String: String]),
    on: replayTask2
)
let replayBadEnv = try decoder.decode(RelayEnvelope<[String: String]>.self, from: replayAuthBad)
try expect(replayBadEnv.type == RelayEventType.error.rawValue, "replay nonce rejected")

chServer.stop()

// Revoke device
try trustStore.revoke(deviceID: deviceID)
let revokedTask = connect(to: devicePort)
defer { revokedTask.cancel(with: .normalClosure, reason: nil) }
let revokedAuthData = try send(
    RelayEnvelope(type: "mac-relay.authorize", payload: ["deviceId": deviceID, "deviceSecret": deviceSecret] as [String: String]),
    on: revokedTask
)
let revokedResult = try decoder.decode(RelayEnvelope<[String: String]>.self, from: revokedAuthData)
try expect(revokedResult.type == RelayEventType.error.rawValue, "revoked device should be rejected")

deviceServer.stop()
server.stop()

print("MacRelayWebSocketServerProbe passed auth=tested standardWebSocket=true port=\(boundPort) seq=\(service.newestSeq) replayEvents=\(replay.payload.events.count)")
