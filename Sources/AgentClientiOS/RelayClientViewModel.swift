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
    @Published public var conversationMessages: [String] = []
    @Published public var draftText = ""
    @Published public var isSending = false
    @Published public var selectedModel = "claude-sonnet-4"
    @Published public var selectedEffort = "medium"
    @Published public var planModeEnabled = false
    @Published public var permissionMode = "Read Only"
    public let modelOptions = ["claude-sonnet-4", "claude-4", "deepseek-v4", "gpt-5"]
    public let efforts = ["low", "medium", "high", "xhigh"]
    public let permissions = ["Read Only", "Default", "Full Access"]

    public let stateMachine = MobileConnectionStateMachine()
    private let httpClient: RelayHTTPClient?
    private let wsClient = RelayWebSocketClient()
    private var token: String?
    private let credentialStore: PairingCredentialStore
    private var pairedHost: String?
    private var pairedPort: UInt16?

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

    /// Pair by first fetching the pairing payload.
    public func pair(host: String, port: UInt16) async throws {
        let client = RelayHTTPClient(host: host, port: port)
        guard stateMachine.attemptPairing() else { throw RelayClientError.invalidPairingInput }
        let pairing = try await client.getPairing()
        pairingCode = pairing.token
        token = pairing.token
        pairedHost = host
        pairedPort = port
        wsClient.connect(host: host, port: pairing.wsPort ?? port)
        try await wsClient.authenticate(token: pairing.token)
        guard stateMachine.pairSuccess() else { return }
        guard stateMachine.startConnect() else { return }
        try await refresh()
        guard stateMachine.connected() else { return }
    }

    /// Claim a pairing from a raw JSON payload string or macrelay:// URI.
    public func claimFromPayload(_ jsonString: String) async throws {
        guard let uri = RelayPairingURI.detect(jsonString) else { throw RelayClientError.invalidPairingInput }
        guard stateMachine.attemptPairing() else { throw RelayClientError.invalidPairingInput }
        let client = RelayHTTPClient(host: uri.host, port: uri.port)

        // Complete the one-time claim — on failure reset state machine
        let claimed: RelayPairingPayload
        do {
            claimed = try await client.claimPairing(claim: uri.claim)
        } catch {
            stateMachine.pairFailed()
            throw error
        }
        pairingCode = claimed.claim
        token = claimed.token
        pairedHost = uri.host
        pairedPort = uri.port
        isConnecting = true
        defer { isConnecting = false }

        if claimed.deviceID != nil, claimed.deviceSecret != nil {
            try? credentialStore.store(token: claimed.token, claim: claimed.claim, expiresAt: claimed.expiresAt)
        }

        wsClient.connect(host: uri.host, port: claimed.wsPort ?? uri.port)
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
        guard let token,
              let host = pairedHost ?? httpClient?.baseURL.host,
              let port = pairedPort ?? httpClient?.baseURL.port.flatMap({ UInt16(exactly: $0) }) else { return }
        guard stateMachine.startReconnect() else { return }
        connectionStatus = "Reconnecting..."
        wsClient.connect(host: host, port: port)
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
        conversationMessages = []
        heartbeatOnline = false
        _ = stateMachine.transition(to: .unpaired)
    }

    public func sendTurn(text: String) async throws {
        guard stateMachine.state == .connected else {
            lastErrorCode = RelayErrorCode.generalError.code
            throw RelayClientError.wsError("not connected")
        }
        isSending = true
        defer { isSending = false }
        conversationMessages.append("[user] \(text)")
        let payload = RelayTurnStartCommandPayload(
            sessionID: sessionSnapshot?.threadID ?? "",
            input: text,
            model: selectedModel,
            effort: selectedEffort,
            planMode: planModeEnabled,
            permissionMode: permissionMode
        )
        let response: RelayEnvelope<[String: String]> = try await wsClient.sendCommand(
            type: .turnStart,
            payload: payload
        )
        // After command acknowledged, refresh snapshot to get updated conversation
        try await refresh()
        updateConversation()
        lastErrorCode = nil
    }

    /// Send current toolbar settings to Mac for hot-switching.
    public func sendSettingsUpdate() async {
        guard stateMachine.state == .connected else { return }
        let payload = RelaySettingsUpdateCommandPayload(
            sessionID: sessionSnapshot?.threadID ?? "",
            model: selectedModel,
            effort: selectedEffort,
            planMode: planModeEnabled,
            permissionMode: permissionMode
        )
        do {
            let _: RelayEnvelope<[String: String]> = try await wsClient.sendCommand(
                type: .settingsUpdate,
                payload: payload
            )
        } catch {
            lastErrorCode = (error as? RelayClientError)?.code ?? RelayErrorCode.generalError.code
        }
    }

    /// Build conversation message list from the latest snapshot.
    public func updateConversation() {
        guard let snap = sessionSnapshot else {
            conversationMessages = []
            return
        }
        var lines: [String] = []
        lines.append("[status] \(snap.status)")
        if let model = snap.model {
            lines.append("[model] \(model)")
        }
        if !snap.assistantText.isEmpty {
            let chunks = snap.assistantText.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            for chunk in chunks {
                lines.append("[assistant] \(chunk)")
            }
        }
        // Add replay events
        for event in replayEvents {
            switch event.type {
            case "turn.delta":
                if let data = try? JSONDecoder().decode(RelayEnvelope<[String: String]>.self, from: event.payloadData) {
                    lines.append("[delta] \(data.payload["delta"] ?? "...")")
                }
            case "turn.completed":
                lines.append("[event] turn completed")
            default:
                break
            }
        }
        conversationMessages = lines
    }

    public func claimFromURL(_ url: URL) async throws {
        try await claimFromPayload(url.absoluteString)
    }
}
