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

func fetch(_ url: URL) throws -> Data {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<Data, Error>?
    URLSession.shared.dataTask(with: url) { data, _, error in
        if let error {
            result = .failure(error)
        } else {
            result = .success(data ?? Data())
        }
        semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + .seconds(10))
    return try result?.get() ?? Data()
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

let snapshotData = try fetch(URL(string: "http://127.0.0.1:\(port)/snapshot")!)
let snapshotEnvelope = try decoder.decode(RelayEnvelope<RelaySnapshotPayload>.self, from: snapshotData)
try expect(snapshotEnvelope.type == RelayEventType.snapshot.rawValue, "snapshot type mismatch")
try expect(snapshotEnvelope.payload.activeSessionID == "thread-http", "snapshot session mismatch")
try expect(snapshotEnvelope.payload.session?.assistantText == "hello http", "snapshot assistant text mismatch")
try expect(snapshotEnvelope.payload.lastEventSeq == service.newestSeq, "snapshot seq mismatch")

let replayData = try fetch(URL(string: "http://127.0.0.1:\(port)/replay?afterSeq=1&maxEvents=10")!)
let replay = try decoder.decode(RelayHTTPReplayPayload.self, from: replayData)
try expect(replay.kind == "events", "replay kind mismatch")
try expect(!replay.events.isEmpty, "replay should contain events")
try expect(replay.events.allSatisfy { $0.seq > 1 }, "replay returned stale event")

server.stop()

print("MacRelayHTTPServerProbe passed port=\(port) seq=\(service.newestSeq) replayEvents=\(replay.events.count)")
