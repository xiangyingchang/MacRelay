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
    private let credentialStore: PairingCredentialStore

    public var hasCredentials: Bool { credentialStore.token != nil }

    public init(host: String = "", port: UInt16 = 0) {
        #if os(macOS) || os(iOS)
        self.credentialStore = KeychainPairingCredentialStore()
        #else
        self.credentialStore = MemoryPairingCredentialStore()
        #endif
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

    /// Claim a pairing from a raw JSON payload string (pasted from Mac Inspector).
    /// Saves device credential to local memory store.
    public func claimFromPayload(_ jsonString: String) async throws {
        guard let data = jsonString.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(RelayPairingPayload.self, from: data)

        guard stateMachine.attemptPairing() else { return }
        let client = RelayHTTPClient(host: payload.host, port: payload.port)

        // Complete the one-time claim
        let claimed = try await client.claimPairing(claim: payload.claim)
        pairingCode = claimed.claim
        token = claimed.token
        isConnecting = true

        if let deviceID = claimed.deviceID, let deviceSecret = claimed.deviceSecret {
            try? credentialStore.store(token: claimed.token, claim: claimed.claim, expiresAt: claimed.expiresAt)
        }

        wsClient.connect(host: payload.host, port: payload.port)
        do {
            try await wsClient.authenticate(token: claimed.token)
            guard stateMachine.pairSuccess() else { return }
            guard stateMachine.startConnect() else { return }
            try await refresh()
            guard stateMachine.connected() else { return }
        } catch {
            _ = stateMachine.authRejected()
            throw error
        }
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

    public func clearPairing() {
        try? credentialStore.clear()
        token = nil
        pairingCode = ""
        sessionSnapshot = nil
        replayEvents = []
        heartbeatOnline = false
        _ = stateMachine.transition(to: .unpaired)
    }
}
