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
    public var currentState: MobileClientState { stateMachine.state }
    public var lastErrorCode: String?
    @Published public var lastHeartbeat: Date?
    @Published public var reconnectAttempt = 0
    private var heartbeatTask: Task<Void, Never>?

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
        guard let uri = RelayPairingURI.detect(jsonString) else { return }
        guard stateMachine.attemptPairing() else { return }
        let client = RelayHTTPClient(host: uri.host, port: uri.port)

        // Complete the one-time claim
        let claimed = try await client.claimPairing(claim: uri.claim)
        pairingCode = claimed.claim
        token = claimed.token
        isConnecting = true

        if let deviceID = claimed.deviceID, let deviceSecret = claimed.deviceSecret {
            try? credentialStore.store(token: claimed.token, claim: claimed.claim, expiresAt: claimed.expiresAt)
        }

        wsClient.connect(host: uri.host, port: uri.port)
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
        startHeartbeatLoop()
    }

    public func refresh() async throws {
        guard stateMachine.state == .connecting || stateMachine.state == .connected else { return }
        isConnecting = true
        do {
            let snap = try await wsClient.getSnapshot()
            sessionSnapshot = snap.payload.session
            heartbeatOnline = true
            let replay = try await wsClient.getReplay(afterSeq: snap.payload.lastEventSeq > 5 ? snap.payload.lastEventSeq - 5 : 0, maxEvents: 20)
            if replay.payload.kind == "events" { replayEvents = replay.payload.events }
            _ = try? await wsClient.heartbeat()
            lastErrorCode = nil
        } catch {
            lastErrorCode = (error as? RelayClientError)?.code ?? RelayErrorCode.generalError.code
        }
        isConnecting = false
    }

    public func reconnect() async {
        guard let token, let host = httpClient?.baseURL.host, let port = httpClient?.baseURL.port else { return }
        guard stateMachine.startReconnect() else { return }
        connectionStatus = "Reconnecting..."
        wsClient.connect(host: host, port: UInt16(port))
        do {
            try await wsClient.authenticate(token: token)
            guard stateMachine.connected() else { return }
            try await refresh()
            lastErrorCode = nil
        } catch {
            _ = stateMachine.authRejected()
            lastErrorCode = RelayErrorCode.authInvalid.code
            connectionStatus = "Auth Failed"
        }
    }

    public func disconnect() {
        wsClient.disconnect()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        _ = stateMachine.networkLost()
    }

    public func startHeartbeatLoop(interval: TimeInterval = 5) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard self.stateMachine.state == .connected else {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    continue
                }
                do {
                    _ = try await self.wsClient.heartbeat()
                    await MainActor.run { self.lastHeartbeat = Date() }
                } catch {
                    await MainActor.run {
                        _ = self.stateMachine.networkLost()
                        self.connectionStatus = "Heartbeat lost"
                        self.reconnectAttempt += 1
                    }
                    // Exponential backoff: 1s, 2s, 4s, ... cap 30s
                    let backoff = min(1 << min(self.reconnectAttempt, 5), 30)
                    try? await Task.sleep(nanoseconds: UInt64(backoff) * 1_000_000_000)
                    await self.reconnect()
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func clearPairing() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        try? credentialStore.clear()
        token = nil
        pairingCode = ""
        sessionSnapshot = nil
        replayEvents = []
        heartbeatOnline = false
        _ = stateMachine.transition(to: .unpaired)
    }

    public func claimFromURL(_ url: URL) async throws {
        try await claimFromPayload(url.absoluteString)
    }
}
