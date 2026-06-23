import AgentClientCore
import AgentClientIO
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let m): return m } }
}

@main
struct AgentClientIOProbe {
    @MainActor
    static func main() async throws {
        // Set up relay service + servers
        let service = MacRelayService(eventCapacity: 20)
        _ = try service.ingest(.notification(method: "thread/started", params: ["thread": ["id": "th", "cwd": "/tmp"]]))
        _ = try service.ingest(.notification(method: "turn/started", params: ["turn": ["id": "turn-1"]]))
        _ = try service.ingest(.notification(method: "item/agentMessage/delta", params: ["delta": "io client"]))
        _ = try service.ingest(.notification(method: "turn/completed", params: ["threadId": "th", "turn": ["id": "turn-1", "status": "completed"]]))

        let httpServer = MacRelayHTTPServer(relayService: service)
        try httpServer.start(port: 0)
        Thread.sleep(forTimeInterval: 0.1)
        let httpPort = httpServer.port!

        let wsServer = MacRelayWebSocketServer(relayService: service, pairingToken: httpServer.token)
        try wsServer.start(port: 0)
        try await Task.sleep(nanoseconds: 150_000_000)
        let wsPort = wsServer.port!

        // HTTP client: pairing + claim
        let httpClient = RelayHTTPClient(host: "127.0.0.1", port: httpPort)
        let pairing = try await httpClient.getPairing()
        guard pairing.protocolVersion == 1 else { throw ProbeError.failed("protocolVersion") }
        guard !pairing.token.isEmpty else { throw ProbeError.failed("token") }
        let claimed = try await httpClient.claimPairing(claim: pairing.claim)
        guard claimed.claimedAt != nil else { throw ProbeError.failed("claimedAt") }

        // WS client: token auth + snapshot + replay + heartbeat
        let wsClient = RelayWebSocketClient()
        wsClient.connect(host: "127.0.0.1", port: wsPort)
        try await wsClient.authenticate(token: httpServer.token)

        let snap = try await wsClient.getSnapshot()
        guard snap.payload.activeSessionID == "th" else { throw ProbeError.failed("snapshot") }
        guard snap.payload.session?.assistantText == "io client" else { throw ProbeError.failed("assistant") }

        let replay = try await wsClient.getReplay(afterSeq: 1, maxEvents: 10)
        guard replay.payload.kind == "events", !replay.payload.events.isEmpty else { throw ProbeError.failed("replay") }

        let hb = try await wsClient.heartbeat()
        guard hb.payload.isOnline else { throw ProbeError.failed("heartbeat") }

        wsClient.disconnect()
        wsServer.stop()
        httpServer.stop()

        print("AgentClientIOProbe passed pairing+claim+wsAuth+snapshot+replay+heartbeat")
    }
}
