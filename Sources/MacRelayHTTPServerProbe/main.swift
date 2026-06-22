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

struct HTTPProbeResponse {
    let statusCode: Int
    let data: Data
}

func fetchResponse(_ url: URL) throws -> HTTPProbeResponse {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<HTTPProbeResponse, Error>?
    URLSession.shared.dataTask(with: url) { data, response, error in
        if let error {
            result = .failure(error)
        } else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            result = .success(HTTPProbeResponse(statusCode: statusCode, data: data ?? Data()))
        }
        semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + .seconds(10))
    return try result?.get() ?? HTTPProbeResponse(statusCode: 0, data: Data())
}

func fetch(_ url: URL) throws -> Data {
    let response = try fetchResponse(url)
    try expect(response.statusCode == 200, "expected HTTP 200 for \(url), got \(response.statusCode)")
    return response.data
}

let service = MacRelayService(eventCapacity: 20)
try ingest(service, .notification(method: "thread/started", params: [
    "thread": ["id": "thread-http", "cwd": "/tmp/project"]
]))
try ingest(service, .notification(method: "turn/started", params: [
    "turn": ["id": "turn-http"]
]))
try ingest(service, .notification(method: "item/agentMessage/delta", params: [
    "delta": "hello http"
]))
try ingest(service, .notification(method: "turn/completed", params: [
    "threadId": "thread-http",
    "turn": ["id": "turn-http", "status": "completed"]
]))

let server = MacRelayHTTPServer(relayService: service)
let port: UInt16 = 48731
try server.start(port: port)
Thread.sleep(forTimeInterval: 0.15)

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

let pairingData = try fetch(URL(string: "http://127.0.0.1:\(port)/pairing")!)
let pairing = try decoder.decode(RelayPairingPayload.self, from: pairingData)
try expect(pairing.host == "127.0.0.1", "pairing host mismatch")
try expect(pairing.port == port, "pairing port mismatch")
try expect(pairing.token == server.token, "pairing token mismatch")
try expect(pairing.claim == server.claim, "pairing claim mismatch")
try expect(pairing.protocolVersion == RelayProtocolVersion.current, "pairing protocol version mismatch")
try expect(pairing.expiresAt > Date(), "pairing expiresAt should be in the future")
try expect(pairing.claimedAt == nil, "pairing should start unclaimed")

let claimData = try fetch(URL(string: "http://127.0.0.1:\(port)/pairing/claim?claim=\(server.claim)")!)
let claimedPairing = try decoder.decode(RelayPairingPayload.self, from: claimData)
try expect(claimedPairing.claimedAt != nil, "pairing claim should set claimedAt")

let secondClaim = try fetchResponse(URL(string: "http://127.0.0.1:\(port)/pairing/claim?claim=\(server.claim)")!)
try expect(secondClaim.statusCode == 409, "pairing claim should be one-time")

let oldToken = server.token
server.rotatePairingToken()
try expect(server.token != oldToken, "rotatePairingToken should change token")

let unauthorizedOldToken = try fetchResponse(URL(string: "http://127.0.0.1:\(port)/snapshot?token=\(oldToken)")!)
try expect(unauthorizedOldToken.statusCode == 401, "old token should stop authorizing after rotation")

let unauthorizedSnapshot = try fetchResponse(URL(string: "http://127.0.0.1:\(port)/snapshot")!)
try expect(unauthorizedSnapshot.statusCode == 401, "snapshot without token should return 401")

let unauthorizedReplay = try fetchResponse(URL(string: "http://127.0.0.1:\(port)/replay?afterSeq=1&maxEvents=10")!)
try expect(unauthorizedReplay.statusCode == 401, "replay without token should return 401")

let snapshotData = try fetch(URL(string: "http://127.0.0.1:\(port)/snapshot?token=\(server.token)")!)
let snapshotEnvelope = try decoder.decode(RelayEnvelope<RelaySnapshotPayload>.self, from: snapshotData)
try expect(snapshotEnvelope.type == RelayEventType.snapshot.rawValue, "snapshot type mismatch")
try expect(snapshotEnvelope.payload.activeSessionID == "thread-http", "snapshot session mismatch")
try expect(snapshotEnvelope.payload.session?.assistantText == "hello http", "snapshot assistant text mismatch")
try expect(snapshotEnvelope.payload.lastEventSeq == service.newestSeq, "snapshot seq mismatch")

let replayData = try fetch(URL(string: "http://127.0.0.1:\(port)/replay?afterSeq=1&maxEvents=10&token=\(server.token)")!)
let replay = try decoder.decode(RelayHTTPReplayPayload.self, from: replayData)
try expect(replay.kind == "events", "replay kind mismatch")
try expect(!replay.events.isEmpty, "replay should contain events")
try expect(replay.events.allSatisfy { $0.seq > 1 }, "replay returned stale event")

server.stop()

print("MacRelayHTTPServerProbe passed port=\(port) seq=\(service.newestSeq) replayEvents=\(replay.events.count) auth=401 pairingProtocol=\(pairing.protocolVersion)")
