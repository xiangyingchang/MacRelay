import AgentClientCore
import AgentClientIO
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let m): return m } }
}

@MainActor
func runRealStateMachineLoopProbe() async throws {
        // Set up relay
        let service = MacRelayService(eventCapacity: 20)
        _ = try service.ingest(.notification(method: "thread/started", params: ["thread": ["id": "th-sm", "cwd": "/tmp"]]))
        _ = try service.ingest(.notification(method: "turn/started", params: ["turn": ["id": "turn-sm"]]))
        _ = try service.ingest(.notification(method: "item/agentMessage/delta", params: ["delta": "state machine"]))
        _ = try service.ingest(.notification(method: "turn/completed", params: ["threadId": "th-sm", "turn": ["id": "turn-sm", "status": "completed"]]))

        let httpServer = MacRelayHTTPServer(relayService: service)
        try httpServer.start(port: 0)
        Thread.sleep(forTimeInterval: 0.1)
        let httpPort = httpServer.port!
        let token = httpServer.token

        var wsServer = MacRelayWebSocketServer(relayService: service, pairingToken: token)

        let sm = MobileConnectionStateMachine()

        // Normal flow: unpaired → paired → connecting → connected
        guard sm.attemptPairing() else { throw ProbeError.failed("pairing") }
        guard sm.pairSuccess() else { throw ProbeError.failed("paired") }
        guard sm.startConnect() else { throw ProbeError.failed("connecting") }

        try wsServer.start(port: 48735)
        try await Task.sleep(nanoseconds: 150_000_000)

        let client = RelayWebSocketClient()
        client.connect(host: "127.0.0.1", port: 48735)
        try await client.authenticate(token: token)
        guard sm.connected() else { throw ProbeError.failed("connected") }

        // Disconnect → offline → reconnect
        wsServer.stop()
        client.disconnect()
        guard sm.networkLost() else { throw ProbeError.failed("offline") }

        for attempt in 1...2 {
            guard sm.startReconnect() else { throw ProbeError.failed("reconnect \(attempt)") }
            try await Task.sleep(nanoseconds: 200_000_000) // let port release
            try wsServer.start(port: 48735)
            try await Task.sleep(nanoseconds: 150_000_000)
            client.connect(host: "127.0.0.1", port: 48735)
            try await client.authenticate(token: token)
            guard sm.connected() else { throw ProbeError.failed("reconnected \(attempt)") }
            wsServer.stop()
            client.disconnect()
            guard sm.networkLost() else { throw ProbeError.failed("offline \(attempt)") }
        }

        // Auth failure → authFailed → unpaired
        try await Task.sleep(nanoseconds: 200_000_000)
        try wsServer.start(port: 48735)
        try await Task.sleep(nanoseconds: 150_000_000)
        guard sm.startReconnect() else { throw ProbeError.failed("reconnect for auth fail") }
        client.connect(host: "127.0.0.1", port: 48735)
        do {
            try await client.authenticate(token: "wrong-token")
            throw ProbeError.failed("wrong token should fail")
        } catch {}
        guard sm.authRejected() else { throw ProbeError.failed("authFailed") }
        guard sm.transition(to: .unpaired) != nil else { throw ProbeError.failed("unpaired after auth fail") }

        client.disconnect()
        wsServer.stop()
        httpServer.stop()

    print("RealStateMachineLoopProbe passed connect+reconnect+backoff+authFail")
}

try await runRealStateMachineLoopProbe()
