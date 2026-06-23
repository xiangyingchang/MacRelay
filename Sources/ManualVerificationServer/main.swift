import AgentClientCore
import Foundation

let service = MacRelayService(eventCapacity: 20)
_ = try service.ingest(.notification(method: "thread/started", params: ["thread": ["id": "th-sm", "cwd": "/tmp"]]))
_ = try service.ingest(.notification(method: "turn/started", params: ["turn": ["id": "turn-sm"]]))
_ = try service.ingest(.notification(method: "item/agentMessage/delta", params: ["delta": "hello from relay verification"]))
_ = try service.ingest(.notification(method: "turn/completed", params: ["threadId": "th-sm", "turn": ["id": "turn-sm", "status": "completed"]]))

let httpServer = MacRelayHTTPServer(relayService: service)
try httpServer.start(port: 48731)
Thread.sleep(forTimeInterval: 0.2)

let wsServer = MacRelayWebSocketServer(relayService: service, pairingToken: httpServer.token)
try wsServer.start(port: 48732)
Thread.sleep(forTimeInterval: 0.2)

// Print pairing URI for the simulator
if let payload = httpServer.pairingPayload {
    let uri = RelayPairingURI(payload: payload).uriString
    print("PAIRING_URI=\(uri)")
    print("RELAY_HTTP=http://\(payload.host):\(payload.port)")
    print("RELAY_WS=ws://\(payload.host):\(payload.port)")
    print("CLAIM=\(payload.claim)")
}

print("SERVERS_RUNNING pid=\(ProcessInfo.processInfo.processIdentifier) http=\(httpServer.port ?? 0) ws=\(wsServer.port ?? 0)")
fflush(stdout)

// Keep alive
while true { Thread.sleep(forTimeInterval: 60) }
