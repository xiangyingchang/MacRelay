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
    /// UI message list built from Mac snapshots plus local sends awaiting acknowledgement.
    @Published public var conversationMessages: [String] = []
    @Published public var draftText = ""
    @Published public var isSending = false
    @Published public var availableSessions: [RelaySessionInfoPayload] = []
    @Published public var workspaceSessions: [RelaySessionInfoPayload] = []
    @Published public var selectedSessionID: String?
    @Published public var sessionFilterText = ""
    /// Toolbar state — synced from snapshot on refresh
    @Published public var selectedModel = ""
    @Published public var selectedEffort = "medium"
    @Published public var planModeEnabled = false
    @Published public var permissionMode = "Read Only"
    @Published public var selectedProvider = "Codex CLI"

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
            let sessions = envelope.payload.availableSessions ?? []
            let wsSessions = envelope.payload.workspaceSessions ?? []
            print("[iOS] onSnapshot: sessions=\(sessions.count) ws=\(wsSessions.count)")
            self.sessionSnapshot = envelope.payload.session
            self.availableSessions = sessions
            self.workspaceSessions = wsSessions
            self.syncToolbarFromSnapshot()
            self.heartbeatOnline = envelope.payload.connection.isOnline
            self.lastErrorCode = nil
            self.updateConversation()
            if let activeID = envelope.payload.activeSessionID {
                self.selectedSessionID = activeID
            }
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
            _ = stateMachine.pairFailed()
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
        try await refreshSnapshot(includeReplay: true)
    }

    private func refreshSnapshot(includeReplay: Bool) async throws {
        guard stateMachine.state == .connecting || stateMachine.state == .connected else { return }
        isConnecting = true
        do {
            let snap = try await wsClient.getSnapshot()
            sessionSnapshot = snap.payload.session
            availableSessions = snap.payload.availableSessions ?? []
            workspaceSessions = snap.payload.workspaceSessions ?? []
            syncToolbarFromSnapshot()
            heartbeatOnline = true
            updateConversation()
            if includeReplay {
                let replay = try await wsClient.getReplay(afterSeq: snap.payload.lastEventSeq > 5 ? snap.payload.lastEventSeq - 5 : 0, maxEvents: 20)
                if replay.payload.kind == "events" { replayEvents = replay.payload.events }
                _ = try? await wsClient.heartbeat()
            }
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
        if let planMode = snap.planMode {
            planModeEnabled = planMode
        }
        if let permissionMode = snap.permissionMode, !permissionMode.isEmpty {
            self.permissionMode = permissionMode
        }
    }

    /// Models available from the Mac snapshot (populated by Codex model/list).
    public var availableModels: [String] {
        sessionSnapshot?.availableModels ?? []
    }

    /// Filtered session list for the session picker UI.
    public var filteredSessions: [RelaySessionInfoPayload] {
        if sessionFilterText.isEmpty { return availableSessions }
        let lower = sessionFilterText.lowercased()
        return availableSessions.filter { s in
            s.sessionID.lowercased().contains(lower) ||
            (s.model?.lowercased().contains(lower) ?? false) ||
            (s.status?.lowercased().contains(lower) ?? false) ||
            (s.cwd?.lowercased().contains(lower) ?? false)
        }
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
        availableSessions = []
        pendingLocalUserMessages = []
        heartbeatOnline = false
        _ = stateMachine.transition(to: .unpaired)
    }

    /// Send a turn. The local user bubble is shown while waiting for Mac acknowledgement.
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
            removePendingUserMessage(text)
            updateConversation()
            lastErrorCode = response.payload["code"] ?? RelayErrorCode.generalError.code
            return
        }
        // Refresh state from Mac and keep polling until this turn completes.
        try await refreshSnapshot(includeReplay: false)
        await pollTurnUntilRenderedAndCompleted(userMessage: text)
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
            permissionMode: permissionMode,
            provider: selectedProvider
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

    /// Fetch session list from Mac.
    public func fetchSessions() async {
        guard stateMachine.state == .connected else { print("[iOS] fetchSessions: not connected"); return }
        do {
            // Use snapshot.get which includes both availableSessions and workspaceSessions
            let snap = try await wsClient.getSnapshot()
            await MainActor.run {
                self.availableSessions = snap.payload.availableSessions ?? []
                self.workspaceSessions = snap.payload.workspaceSessions ?? []
                print("[iOS] fetchSessions: active=\(self.availableSessions.count) ws=\(self.workspaceSessions.count)")
            }
        } catch {
            print("[iOS] fetchSessions error: \(error)")
            await MainActor.run { self.lastErrorCode = (error as? RelayClientError)?.code ?? RelayErrorCode.generalError.code }
        }
    }

    /// Select (switch to) a session on Mac. Mac will stop the current
    /// thread and start a fresh one in the selected session's project context.
    public func selectSession(sessionID: String) async throws {
        guard stateMachine.state == .connected else { throw RelayClientError.wsError("not connected") }
        self.selectedSessionID = sessionID
        let payload = RelaySessionSelectCommandPayload(sessionID: sessionID)
        let _: RelayEnvelope<[String: String]> = try await wsClient.sendCommand(
            type: .sessionSelect,
            payload: payload
        )
        try await refresh()
    }

    /// Create a new session on Mac. Mac creates a thread (even without prompt)
    /// and broadcasts it via availableSessions. We poll until the count
    /// increases — just checking non-empty is wrong when sessions already exist.
    public func startNewSession(initialPrompt: String? = nil) async throws {
        guard stateMachine.state == .connected else { throw RelayClientError.wsError("not connected") }
        let existingIDs = Set(self.availableSessions.map(\.sessionID))
        let existingCount = self.availableSessions.count
        let payload = RelaySessionStartCommandPayload(
            cwd: sessionSnapshot?.cwd ?? FileManager.default.currentDirectoryPath,
            model: selectedModel.isEmpty ? nil : selectedModel,
            effort: selectedEffort,
            planMode: planModeEnabled,
            permissionMode: permissionMode,
            initialPrompt: initialPrompt
        )
        let _: RelayEnvelope<[String: String]> = try await wsClient.sendCommand(
            type: .sessionStart,
            payload: payload
        )
        // The Mac init chain is async (initialize → model/list → thread/start).
        // Poll snapshot until a new session appears.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            try? await refreshSnapshot(includeReplay: false)
            if self.availableSessions.count > existingCount {
                return
            }
        }
    }

    /// Build conversation message list from the latest snapshot — Single Source of Truth.
    public func updateConversation() {
        guard let snap = sessionSnapshot else {
            conversationMessages = pendingLocalUserMessages.map { "[user] \($0)" }
            return
        }
        var lines: [String] = []
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
        conversationMessages = lines
    }

    private func pollTurnUntilRenderedAndCompleted(userMessage: String) async {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline && !Task.isCancelled {
            if let turn = sessionSnapshot?.turns.last(where: { $0.userMessage == trimmed }),
               turn.isCompleted {
                return
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            try? await refreshSnapshot(includeReplay: false)
        }
    }

    private func appendPendingUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingLocalUserMessages.append(trimmed)
        updateConversation()
    }

    private func removePendingUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = pendingLocalUserMessages.firstIndex(of: trimmed) {
            pendingLocalUserMessages.remove(at: index)
        }
    }

    public func claimFromURL(_ url: URL) async throws {
        try await claimFromPayload(url.absoluteString)
    }
}
