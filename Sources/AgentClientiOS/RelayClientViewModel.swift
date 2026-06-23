import AgentClientCore
import AgentClientIO
import Foundation

/// View model for the iOS relay client, exposing connection state and
/// session data in an ObservableObject suitable for SwiftUI binding.
@MainActor
public final class RelayClientViewModel: ObservableObject {
    @Published public var connectionStatus: String = "Disconnected"
    @Published public var sessionSnapshot: RelaySessionSnapshotPayload?
    @Published public var replayEvents: [StoredRelayEvent] = []
    @Published public var heartbeatOnline = false
    @Published public var pairingCode: String = ""
    @Published public var isConnecting = false

    public let stateMachine = MobileConnectionStateMachine()
    private let httpClient: RelayHTTPClient?
    private let wsClient = RelayWebSocketClient()
    private var token: String?

    public init(host: String = "", port: UInt16 = 0) {
        if !host.isEmpty {
            self.httpClient = RelayHTTPClient(host: host, port: port)
        } else {
            self.httpClient = nil
        }
        stateMachine.onTransition = { [weak self] t in
            Task { @MainActor in
                self?.connectionStatus = t.to.rawValue.capitalized
            }
        }
    }

    public func pair(host: String, port: UInt16) async throws {
        let client = RelayHTTPClient(host: host, port: port)
        guard stateMachine.attemptPairing() else { return }
        let pairing = try await client.getPairing()
        pairingCode = pairing.token
        token = pairing.token
        wsClient.connect(host: host, port: port)
        try await wsClient.authenticate(token: pairing.token)
        guard stateMachine.pairSuccess() else { return }
        guard stateMachine.startConnect() else { return }
        try await refresh()
        guard stateMachine.connected() else { return }
    }

    public func refresh() async throws {
        guard stateMachine.state == .connecting || stateMachine.state == .connected else { return }
        isConnecting = true
        let snap = try await wsClient.getSnapshot()
        sessionSnapshot = snap.payload.session
        heartbeatOnline = true
        let replay = try await wsClient.getReplay(afterSeq: snap.payload.lastEventSeq > 5 ? snap.payload.lastEventSeq - 5 : 0, maxEvents: 20)
        if replay.payload.kind == "events" { replayEvents = replay.payload.events }
        _ = try? await wsClient.heartbeat()
        isConnecting = false
    }

    public func disconnect() {
        wsClient.disconnect()
        _ = stateMachine.networkLost()
    }
}
