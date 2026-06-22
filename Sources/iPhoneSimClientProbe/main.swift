import AgentClientCore
import Foundation

/// Simulated iPhone client that exercises the full MacRelay protocol flow:
/// pairing → claim → WebSocket auth → snapshot/replay/heartbeat → reconnect.
///
/// Does not require a real iOS device or UI.  Runs locally against an ephemeral
/// relay server.
enum ProbeError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let m): return m } }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ProbeError.failed(message) }
}

func ingest(_ service: MacRelayService, _ event: CodexAppServerEvent) throws {
    _ = try service.ingest(event)
}

// MARK: - HTTP fetch helpers

struct HTTPProbeResponse {
    let statusCode: Int
    let data: Data
}

func httpGet(_ url: URL) throws -> HTTPProbeResponse {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<HTTPProbeResponse, Error>?
    URLSession.shared.dataTask(with: url) { data, response, error in
        if let error {
            result = .failure(error)
        } else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            result = .success(HTTPProbeResponse(statusCode: code, data: data ?? Data()))
        }
        semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + .seconds(10))
    return try result?.get() ?? HTTPProbeResponse(statusCode: 0, data: Data())
}

// MARK: - WebSocket helpers

func wsConnect(to port: UInt16) -> URLSessionWebSocketTask {
    let session = URLSession(configuration: .ephemeral)
    let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/relay")!)
    task.resume()
    return task
}

func wsSend<Payload: Encodable>(_ envelope: RelayEnvelope<Payload>, on task: URLSessionWebSocketTask) throws -> Data {
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

    let recvSemaphore = DispatchSemaphore(value: 0)
    var result: Result<Data, Error>?
    task.receive {
        switch $0 {
        case .success(.data(let d)): result = .success(d)
        case .success(.string(let s)): result = .success(Data(s.utf8))
        case .failure(let e): result = .failure(e)
        @unknown default: result = .failure(ProbeError.failed("unknown frame"))
        }
        recvSemaphore.signal()
    }
    _ = recvSemaphore.wait(timeout: .now() + .seconds(10))
    return try result?.get() ?? Data()
}

// MARK: - Test flow

let service = MacRelayService(eventCapacity: 20)
try ingest(service, .notification(method: "thread/started", params: ["thread": ["id": "th-iphone", "cwd": "/tmp/proj"]]))
try ingest(service, .notification(method: "turn/started", params: ["turn": ["id": "turn-iphone"]]))
try ingest(service, .notification(method: "item/agentMessage/delta", params: ["delta": "iphone client"]))
try ingest(service, .notification(method: "turn/completed", params: ["threadId": "th-iphone", "turn": ["id": "turn-iphone", "status": "completed"]]))

let httpServer = MacRelayHTTPServer(relayService: service)
try httpServer.start(port: 0)
Thread.sleep(forTimeInterval: 0.15)
let httpPort = try httpServer.port ?? { throw ProbeError.failed("HTTP port") }()

// Step 1: read pairing payload (simulates QR scan)
let pairingResp = try httpGet(URL(string: "http://127.0.0.1:\(httpPort)/pairing")!)
try expect(pairingResp.statusCode == 200, "pairing fetch ok")
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

let pairing = try decoder.decode(RelayPairingPayload.self, from: pairingResp.data)
try expect(pairing.protocolVersion == 1, "protocol version")
try expect(!pairing.token.isEmpty, "pairing token non-empty")
try expect(!pairing.claim.isEmpty, "pairing claim non-empty")

// Step 2: complete claim (simulates iPhone claiming the pairing)
let claimResp = try httpGet(URL(string: "http://127.0.0.1:\(httpPort)/pairing/claim?claim=\(pairing.claim)")!)
try expect(claimResp.statusCode == 200, "claim ok")
let claimed = try decoder.decode(RelayPairingPayload.self, from: claimResp.data)
try expect(claimed.claimedAt != nil, "claimedAt set")

// Step 2b: second claim fails (one-time enforcement)
let secondClaim = try httpGet(URL(string: "http://127.0.0.1:\(httpPort)/pairing/claim?claim=\(pairing.claim)")!)
try expect(secondClaim.statusCode == 409, "second claim is conflict")

let wsServer = MacRelayWebSocketServer(relayService: service, pairingToken: httpServer.token)
try wsServer.start(port: 0)
try expect(wsServer.waitUntilReady(), "ws ready")
let wsPort = try wsServer.port ?? { throw ProbeError.failed("WS port") }()

// Step 3a: auth failure — wrong token
let badTask = wsConnect(to: wsPort)
defer { badTask.cancel(with: .normalClosure, reason: nil) }
let badAuth = try wsSend(
    RelayEnvelope(type: "mac-relay.authorize", payload: ["token": "wrong"] as [String: String]),
    on: badTask
)
let badObj = try JSONSerialization.jsonObject(with: badAuth) as? [String: Any] ?? [:]
try expect(badObj["type"] as? String == "error", "wrong token → error")

// Step 3b: auth success — correct token
let goodTask = wsConnect(to: wsPort)
defer { goodTask.cancel(with: .normalClosure, reason: nil) }
let authData = try wsSend(
    RelayEnvelope(type: "mac-relay.authorize", payload: ["token": httpServer.token] as [String: String]),
    on: goodTask
)
let authObj = try JSONSerialization.jsonObject(with: authData) as? [String: Any] ?? [:]
try expect(authObj["type"] as? String == "mac-relay.authenticated", "authenticated")

// Step 4: snapshot.get
let snapData = try wsSend(
    RelayEnvelope(type: RelayCommandType.snapshotGet.rawValue, payload: [:] as [String: String]),
    on: goodTask
)
let snap = try decoder.decode(RelayEnvelope<RelaySnapshotPayload>.self, from: snapData)
try expect(snap.payload.activeSessionID == "th-iphone", "snapshot session")
try expect(snap.payload.session?.assistantText == "iphone client", "assistant text")

// Step 5: replay.from
let replayData = try wsSend(
    RelayEnvelope(type: RelayCommandType.replayFrom.rawValue, payload: RelayReplayRequestPayload(afterSeq: 1, maxEvents: 10)),
    on: goodTask
)
let replay = try decoder.decode(RelayEnvelope<RelayHTTPReplayPayload>.self, from: replayData)
try expect(replay.payload.kind == "events", "replay")
try expect(!replay.payload.events.isEmpty, "replay has events")

// Step 6: heartbeat.ping
let hbData = try wsSend(
    RelayEnvelope(type: RelayCommandType.heartbeatPing.rawValue, payload: [:] as [String: String]),
    on: goodTask
)
let hb = try decoder.decode(RelayEnvelope<ConnectionSnapshotPayload>.self, from: hbData)
try expect(hb.payload.isOnline, "heartbeat online")

// Step 7: reconnect — disconnect and fresh WS auth
goodTask.cancel(with: .normalClosure, reason: nil)
Thread.sleep(forTimeInterval: 0.1)
let reconnectTask = wsConnect(to: wsPort)
defer { reconnectTask.cancel(with: .normalClosure, reason: nil) }
let reauthData = try wsSend(
    RelayEnvelope(type: "mac-relay.authorize", payload: ["token": httpServer.token] as [String: String]),
    on: reconnectTask
)
let reauthObj = try JSONSerialization.jsonObject(with: reauthData) as? [String: Any] ?? [:]
try expect(reauthObj["type"] as? String == "mac-relay.authenticated", "reconnect auth")

let snap2Data = try wsSend(
    RelayEnvelope(type: RelayCommandType.snapshotGet.rawValue, payload: [:] as [String: String]),
    on: reconnectTask
)
let snap2 = try decoder.decode(RelayEnvelope<RelaySnapshotPayload>.self, from: snap2Data)
try expect(snap2.payload.activeSessionID == "th-iphone", "reconnect snapshot")

wsServer.stop()
httpServer.stop()

print("iPhoneSimClientProbe passed flow=pairing+claim+wsAuth+snapshot+replay+heartbeat+reconnect")
