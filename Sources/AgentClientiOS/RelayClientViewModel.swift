import AgentClientCore
import AgentClientIO
import Foundation

/// View model for the iOS relay client, exposing connection state and
/// session data in an ObservableObject suitable for SwiftUI binding.
/// All toolbar state is driven by Mac snapshot — no hardcoded model lists.
@MainActor
public final class RelayClientViewModel: ObservableObject {
    @Published public var connectionStatus: String = "Disconnected"
    @Published public var sessionSnapshot: RelaySessionSnapshotPayload?
    @Published public var replayEvents: [StoredRelayEvent] = []
    @Published public var heartbeatOnline = false
    @Published public var pairingCode: String = ""
    @Published public var isConnecting = false
    /// UI message list — driven ONLY by Mac snapshot, never optimistic.
    @Published public var conversationMessages: [String] = []
    @Published public var draftText = ""
    @Published public var isSending = false
    /// Toolbar state — synced from snapshot on refresh
    @Published public var selectedModel = ""
    @Published public var selectedEffort = "medium"
    @Published public var planModeEnabled = false
    @Published public var permissionMode = "Read Only"

    public let stateMachine = MobileConnectionStateMachine()
    private let httpClient: RelayHTTPClient?
    private let wsClient = RelayWebSocketClient()
    private var token: String?
    private let credentialStore: PairingCredentialStore
    private var pairedHost: String?
    private var pairedPort: UInt16?
    private var pendingLocalUserMessages: [String] = []

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
        wsClient.onSnapshot = { [weak self] envelope in
            guard let self else { return }
            self.sessionSnapshot = envelope.payload.session
            self.syncToolbarFromSnapshot()
            self.heartbeatOnline = envelope.payload.connection.isOnline
            self.lastErrorCode = nil
            self.updateConversation()
        }
        wsClient.onConnectionLost = { [weak self] _ in
            guard let self else { return }
            _ = self.stateMachine.networkLost()
            self.heartbeatOnline = false
            self.connectionStatus = "Connection lost"
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
            syncToolbarFromSnapshot()
            heartbeatOnline = true
            updateConversation()
            let replay = try await wsClient.getReplay(afterSeq: snap.payload.lastEventSeq > 5 ? snap.payload.lastEventSeq - 5 : 0, maxEvents: 20)
            if replay.payload.kind == "events" { replayEvents = replay.payload.events }
            _ = try? await wsClient.heartbeat()
            updateConversation()
            lastErrorCode = nil
        } catch {
            lastErrorCode = (error as? RelayClientError)?.code ?? RelayErrorCode.generalError.code
        }
        isConnecting = false
    }

    /// Synchronise toolbar state from the latest Mac snapshot — Single Source of Truth.
    private func syncToolbarFromSnapshot() {
        guard let snap = sessionSnapshot else { return }
        if let model = snap.model, !model.isEmpty {
            selectedModel = model
        }
        if let effort = snap.effort, !effort.isEmpty {
            selectedEffort = effort
        }
    }

    /// Models available from the Mac snapshot (populated by Codex model/list).
    public var availableModels: [String] {
        sessionSnapshot?.availableModels ?? []
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
        pendingLocalUserMessages = []
        heartbeatOnline = false
        _ = stateMachine.transition(to: .unpaired)
    }

    /// Send a turn — NO optimistic update. UI renders only after Mac confirms.
    public func sendTurn(text: String) async throws {
        guard stateMachine.state == .connected else {
            lastErrorCode = RelayErrorCode.generalError.code
            throw RelayClientError.wsError("not connected")
        }
        isSending = true
        defer { isSending = false }
        appendPendingUserMessage(text)
        let payload = RelayTurnStartCommandPayload(
            sessionID: sessionSnapshot?.threadID ?? "",
            input: text,
            model: selectedModel.isEmpty ? nil : selectedModel,
            effort: selectedEffort,
            planMode: planModeEnabled,
            permissionMode: permissionMode
        )
        // Send and wait for Mac acknowledgement
        let response: RelayEnvelope<[String: String]> = try await wsClient.sendCommand(
            type: .turnStart,
            payload: payload
        )
        // Check for error — Mac may reject if previous turn is still processing
        guard response.type != RelayEventType.error.rawValue else {
            updateConversation()
            lastErrorCode = response.payload["code"] ?? RelayErrorCode.generalError.code
            return
        }
        // Refresh state from Mac (Single Source of Truth)
        try await refresh()
        updateConversation()
        lastErrorCode = nil
    }

    /// Send current toolbar settings to Mac for hot-switching.
    public func sendSettingsUpdate() async {
        guard stateMachine.state == .connected else { return }
        let payload = RelaySettingsUpdateCommandPayload(
            sessionID: sessionSnapshot?.threadID ?? "",
            model: selectedModel.isEmpty ? nil : selectedModel,
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

    /// Build conversation message list from the latest snapshot — Single Source of Truth.
    public func updateConversation() {
        guard let snap = sessionSnapshot else {
            conversationMessages = pendingLocalUserMessages.map { "[user] \($0)" }
            return
        }
        var lines: [String] = []
        lines.append("[status] \(snap.status)")
        if let model = snap.model {
            lines.append("[model] \(model)")
        }

        let turns = snap.turns.isEmpty
            ? [RelayTurnSnapshotPayload(
                id: snap.threadID,
                userMessage: nil,
                assistantText: snap.assistantText,
                isCompleted: snap.status == "completed"
            )]
            : snap.turns

        for turn in turns {
            if let userMsg = turn.userMessage, !userMsg.isEmpty {
                lines.append("[user] \(userMsg)")
            }
            if !turn.assistantText.isEmpty {
                let chunks = turn.assistantText
                    .components(separatedBy: "\n\n")
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                for chunk in chunks {
                    lines.append("[assistant] \(chunk)")
                }
            }
        }

        let renderedUserMessages = Set(turns.compactMap(\.userMessage))
        pendingLocalUserMessages.removeAll { renderedUserMessages.contains($0) }
        for pending in pendingLocalUserMessages {
            lines.append("[user] \(pending)")
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

    private func appendPendingUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingLocalUserMessages.append(trimmed)
        updateConversation()
    }

    public func claimFromURL(_ url: URL) async throws {
        try await claimFromPayload(url.absoluteString)
    }
}
