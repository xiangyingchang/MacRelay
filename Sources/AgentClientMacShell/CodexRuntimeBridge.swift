import AgentClientCore
import Foundation

// MARK: - Errors

public enum MacRelayBridgeError: Error, LocalizedError {
    case turnInProgress(String)
    case sessionNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .turnInProgress(let msg): return msg
        case .sessionNotFound(let id): return "Session not found: \(id)"
        }
    }
}

// MARK: - Pending Request Registry

enum PendingRequestKind: String {
    case initialize
    case modelList
    case threadStart
    case turnStart
    case settingsUpdate
}

struct PendingRequest {
    let id: Int
    let kind: PendingRequestKind
    let createdAt: Date
}

// MARK: - CodexRuntimeBridge

@MainActor
final class CodexRuntimeBridge: ObservableObject, MacRelayRuntimeBridge {
    @Published private(set) var detection = CodexCLIDetector.detect(includeVersion: false)
    @Published private(set) var statusText = "Codex CLI detection pending"
    @Published private(set) var modelNames: [String] = []
    @Published private(set) var currentThreadID: String?
    @Published private(set) var snapshot = SessionSnapshot()
    @Published private(set) var latestTurnID: String?
    @Published private(set) var rateLimitText = ""
    @Published private(set) var isAppServerRunning = false
    @Published private(set) var isInitialized = false
    @Published private(set) var isInitializing = false
    @Published private(set) var sessions: [RelaySessionInfoPayload] = []
    @Published private(set) var selectedSessionID: String?

    var selectedSessionCWD: String? {
        guard let id = selectedSessionID else { return nil }
        return sessions.first(where: { $0.sessionID == id })?.cwd
    }

    var onTurnIDChanged: ((String?) -> Void)?
    var onEventReceived: ((CodexAppServerEvent) -> Void)?
    /// Fires when a new thread starts (thread/started notification).
    /// The MacShellViewModel uses this to clear the conversation view
    /// so a new session doesn't inherit old messages.
    var onThreadStarted: ((String) -> Void)?
    var isProcessingTurn: Bool { pendingDraft != nil }

    // MARK: - Private state
    private var client: CodexAppServerClient?
    private let reducer = SessionStateReducer()
    private var pendingRequests: [Int: PendingRequest] = [:]

    // Stashed draft for async init → thread → turn chain
    private var pendingDraft: DraftParams?

    private struct DraftParams {
        let cwd: String
        let text: String
        let model: String?
        let effort: String?
        let threadSandbox: String   // kebab-case for thread/start
        let turnSandbox: String     // camelCase for turn/start
        let approvalPolicy: String
    }

    var isReadyForAppServer: Bool {
        detection.isInstalled && client == nil
    }

    // MARK: - Detection

    func refreshDetection() {
        statusText = "Checking Codex CLI..."
        Task.detached {
            let result = CodexCLIDetector.detect()
            await MainActor.run {
                self.detection = result
                self.statusText = result.isInstalled
                    ? "Codex CLI found: \(result.version ?? result.executablePath ?? "installed")"
                    : "Codex CLI not found"
            }
        }
    }

    // MARK: - App Server Lifecycle

    func startAppServer(cwd: String) throws {
        guard let command = detection.executablePath else {
            statusText = "Codex CLI not installed"
            return
        }

        let nextClient = CodexAppServerClient(codexCommand: command, cwd: cwd)
        nextClient.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        try nextClient.start()
        client = nextClient
        isAppServerRunning = true
        statusText = "Codex app-server started"
    }

    func stopAppServer() {
        client?.stop()
        client = nil
        isAppServerRunning = false
        isInitialized = false
        currentThreadID = nil
        latestTurnID = nil
        pendingRequests.removeAll()
        pendingDraft = nil
        statusText = "Codex app-server stopped"
    }

    // MARK: - High-level: enqueue a draft (auto-chains init → thread → turn)

    /// Enqueues a user draft. If the app-server isn't initialized yet,
    /// starts the full chain: startAppServer → initialize → model/list → thread/start → turn/start.
    func enqueueDraft(
        cwd: String,
        text: String,
        model: String?,
        effort: String?,
        threadSandbox: String,
        turnSandbox: String,
        approvalPolicy: String
    ) throws {
        guard !isProcessingTurn else {
            throw MacRelayBridgeError.turnInProgress("previous turn still processing — wait for completion")
        }
        pendingDraft = DraftParams(
            cwd: cwd, text: text,
            model: model, effort: effort,
            threadSandbox: threadSandbox, turnSandbox: turnSandbox,
            approvalPolicy: approvalPolicy
        )
        latestTurnID = nil
        clearActiveTurn()

        if !isAppServerRunning {
            try startAppServer(cwd: cwd)
        }

        if !isInitialized {
            // Start init chain. Response handler will continue the chain:
            // initialize response → initialized notification → model/list
            // model/list response → firePendingDraft → thread/start
            // thread/started notification → turn/start
            try initialize()
            statusText = "Initializing → will auto-send draft..."
        } else if currentThreadID == nil {
            // Initialized but no thread yet
            try startThread(draft: pendingDraft!)
        } else {
            // Both initialized and thread exists — send turn directly
            try startTurnFromDraft()
        }
    }

    func resolveApproval(requestID: Int, decision: String) throws {
        try client?.response(id: requestID, result: ["decision": decision])
        apply(.approvalResolved(requestID: requestID, decision: decision))
        statusText = "approval \(decision)"
    }

    // MARK: - JSON-RPC Requests (low-level)

    @discardableResult
    func initialize() throws -> Int {
        isInitializing = true
        let requestID = try sendRequest(
            method: "initialize",
            kind: .initialize,
            params: [
                "clientInfo": [
                    "name": "agent-client-mac-shell",
                    "title": "Agent Client Mac Shell",
                    "version": "0.1.0"
                ],
                "capabilities": [
                    "experimentalApi": true
                ]
            ]
        )
        statusText = "initialize requested"
        return requestID
    }

    @discardableResult
    func listModels() throws -> Int {
        let requestID = try sendRequest(method: "model/list", kind: .modelList, params: [:])
        statusText = "model/list requested"
        return requestID
    }

    @discardableResult
    func startThread(
        cwd: String,
        model: String?,
        effort: String?,
        sandbox: String,
        approvalPolicy: String
    ) throws -> Int {
        var params: [String: Any] = [
            "cwd": cwd,
            "sandbox": sandbox,
            "approvalPolicy": approvalPolicy,
            "sessionStartSource": "startup"
        ]
        if let model { params["model"] = model }
        if let effort { params["effort"] = effort }

        let requestID = try sendRequest(method: "thread/start", kind: .threadStart, params: params)
        statusText = "thread/start sbox=\(sandbox) [build:4]"
        return requestID
    }

    @discardableResult
    func startTurn(
        threadID: String,
        text: String,
        model: String?,
        effort: String?,
        approvalPolicy: String?,
        sandboxPolicy: String?
    ) throws -> Int {
        var params: [String: Any] = [
            "threadId": threadID,
            "input": [["type": "text", "text": text]]
        ]
        if let model { params["model"] = model }
        if let effort { params["effort"] = effort }
        if let approvalPolicy { params["approvalPolicy"] = approvalPolicy }
        if let sandboxPolicy { params["sandboxPolicy"] = ["type": sandboxPolicy] }

        let requestID = try sendRequest(method: "turn/start", kind: .turnStart, params: params)
        statusText = "turn/start sbox=\(sandboxPolicy ?? "nil") [build:4]"
        return requestID
    }

    // MARK: - Settings Update

    /// Sends thread/settings/update to the app-server.
    /// Only call when isInitialized == true and currentThreadID != nil.
    /// The app-server applies these settings to the current thread and
    /// responds (via notification `thread/settings/updated`).
    ///
    /// Parameter sandboxPolicy uses camelCase values matching turn/start:
    ///   "readOnly", "workspaceWrite", "dangerFullAccess".
    @discardableResult
    func updateSettings(
        model: String?,
        effort: String?,
        approvalPolicy: String?,
        sandboxPolicy: String?
    ) throws -> Int {
        guard let currentThreadID else {
            throw CodexAppServerClientError.notStarted
        }
        var params: [String: Any] = ["threadId": currentThreadID]
        if let model { params["model"] = model }
        if let effort { params["effort"] = effort }
        if let approvalPolicy { params["approvalPolicy"] = approvalPolicy }
        if let sandboxPolicy { params["sandboxPolicy"] = ["type": sandboxPolicy] }

        let requestID = try sendRequest(method: "thread/settings/update", kind: .settingsUpdate, params: params)
        statusText = "thread/settings/update"
        return requestID
    }

    // MARK: - Private: request management

    private func sendRequest(method: String, kind: PendingRequestKind, params: Any) throws -> Int {
        guard let client else {
            throw CodexAppServerClientError.notStarted
        }
        logPayload(method: method, params: params)
        let requestID = try client.request(method: method, params: params)
        pendingRequests[requestID] = PendingRequest(id: requestID, kind: kind, createdAt: Date())
        return requestID
    }

    private func logPayload(method: String, params: Any) {
        #if DEBUG
        guard method == "thread/start" || method == "turn/start" || method == "thread/settings/update" else {
            return
        }
        var fields: [String] = []
        if let dict = params as? [String: Any] {
            if let sandbox = dict["sandbox"] as? String {
                fields.append("sandbox=\(sandbox)")
            }
            if let sandboxPolicy = dict["sandboxPolicy"] as? [String: Any],
               let type = sandboxPolicy["type"] as? String {
                fields.append("sandboxPolicy.type=\(type)")
            }
            if let approvalPolicy = dict["approvalPolicy"] as? String {
                fields.append("approvalPolicy=\(approvalPolicy)")
            }
            if let model = dict["model"] as? String {
                fields.append("model=\(model)")
            }
            if let effort = dict["effort"] as? String {
                fields.append("effort=\(effort)")
            }
        }
        let suffix = fields.isEmpty ? "params=<no tracked fields>" : fields.joined(separator: " ")
        print("[CodexRuntimeBridge] \(method) \(suffix)")
        #endif
    }

    // MARK: - Private: event handling

    private func handle(_ event: CodexAppServerEvent) {
        // Process notification side-effects BEFORE forwarding to relay,
        // so recordSession (which populates the sessions array) completes
        // before the relay broadcast snapshot checks runtime.sessions.
        if case let .notification(method, params) = event, method == "thread/started" {
            if let threadID = params?["id"] as? String
                ?? (params?["thread"] as? [String: Any])?["id"] as? String {
                currentThreadID = threadID
                recordSession(threadID: threadID, params: params)
                // Set session title from the user's first message
                if let draft = pendingDraft, !draft.text.isEmpty,
                   let idx = sessions.firstIndex(where: { $0.sessionID == threadID }) {
                    sessions[idx].title = draft.text
                }
                firePendingTurn(threadID: threadID)
                onThreadStarted?(threadID)
            }
        }

        // Inject user message from pending draft into turn/started events
        let augmentedEvent: CodexAppServerEvent
        if case let .notification(method, params) = event, method == "turn/started", let draft = pendingDraft {
            var augmentedParams = params ?? [:]
            augmentedParams["input"] = draft.text
            augmentedEvent = .notification(method: method, params: augmentedParams)
        } else {
            augmentedEvent = event
        }
        onEventReceived?(augmentedEvent)

        switch event {
        case let .response(id, result, error):
            handleResponse(id: id, result: result, error: error)

        case let .stderr(line):
            statusText = "stderr: \(line)"

        case let .raw(line):
            statusText = "raw: \(line)"

        case let .serverRequest(_, method, _):
            statusText = "server request: \(method)"

        case let .notification(method, params) where method == "account/rateLimits/updated":
            statusText = "rateLimits updated"
            rateLimitText = formatRateLimits(params)

        case let .notification(method, params) where method == "thread/started":
            statusText = "thread started"
            // recordSession + firePendingTurn handled before onEventReceived above
            _ = params

        case let .notification(method, params) where method == "turn/started":
            let extracted = Self.extractTurnID(from: params)
            if let turnID = extracted {
                latestTurnID = turnID
            }
            // Set session title from the user's first real message if the
            // session was created with empty text (session.start no-prompt).
            if let threadID = currentThreadID,
               let idx = sessions.firstIndex(where: { $0.sessionID == threadID }),
               (sessions[idx].title ?? "").isEmpty,
               let draft = pendingDraft, !draft.text.isEmpty {
                sessions[idx].title = draft.text
            }
            print("[Log] Received CLI Turn Started: \(extracted ?? "?")")

        case let .notification(method, params) where method == "item/agentMessage/delta":
            print("[Log] Received CLI Delta: \(params?["messageID"] ?? params?["messageId"] ?? params?["delta"] ?? "?")")
            // Delta logged; reducer handles the text append

        case let .notification(method, params) where method == "turn/completed":
            let turnID = Self.extractTurnID(from: params) ?? "?"
            print("[Log] Received CLI Turn Completed: \(turnID)")
            pendingDraft = nil

        case let .notification(method, _):
            statusText = "notification: \(method)"
            print("[Log] Notification: \(method)")

        #if os(macOS)
        case let .exit(code, _):
            client = nil
            isAppServerRunning = false
            isInitialized = false
            isInitializing = false
            currentThreadID = nil
            latestTurnID = nil
            pendingRequests.removeAll()
            statusText = "app-server exited: \(code)"
        #endif
        }

        apply(reducer.actions(from: event))
    }

    private func handleResponse(id: Int, result: [String: Any]?, error: Any?) {
        let pending = pendingRequests.removeValue(forKey: id)

        if let error {
            statusText = "response \(id) error: \(error)"
            isInitializing = false
            let errorDict = error as? [String: Any]
            let message = errorDict?["message"] as? String ?? "\(error)"
            apply(.error(params: [
                "error": [
                    "message": message,
                    "codexErrorInfo": errorDict?["codexErrorInfo"] as? String ?? ""
                ]
            ]))
            return
        }

        guard let kind = pending?.kind else {
            statusText = "response \(id) (untracked)"
            return
        }

        switch kind {
        case .initialize:
            statusText = "initialized → sending model/list..."
            try? client?.notification(method: "initialized")
            _ = try? listModels()

        case .modelList:
            statusText = "model/list received"
            updateModels(from: result)
            isInitialized = true
            isInitializing = false
            firePendingDraft()

        case .threadStart:
            statusText = "thread/start response"
            // threadID usually comes from thread/started notification (handled above),
            // but some versions may return it in response
            if let threadID = result?["id"] as? String
                ?? (result?["thread"] as? [String: Any])?["id"] as? String {
                if currentThreadID == nil {
                    currentThreadID = threadID
                    firePendingTurn(threadID: threadID)
                }
            }

        case .turnStart:
            statusText = "turn active"
            if let turnID = Self.extractTurnID(from: result) {
                latestTurnID = turnID
            }

        case .settingsUpdate:
            statusText = "settings updated"
        }
    }

    private func apply(_ actions: [SessionReducerAction]) {
        guard !actions.isEmpty else { return }
        var nextSnapshot = snapshot
        for action in actions {
            reducer.reduce(&nextSnapshot, action: action)
        }
        snapshot = nextSnapshot
    }

    private func apply(_ action: SessionReducerAction) {
        apply([action])
    }

    private func clearActiveTurn() {
        var nextSnapshot = snapshot
        nextSnapshot.activeTurn = nil
        if nextSnapshot.status == .completed || nextSnapshot.status == .failed {
            nextSnapshot.status = .active
        }
        snapshot = nextSnapshot
    }

    private static func extractTurnID(from params: [String: Any]?) -> String? {
        guard let params else { return nil }
        return params["id"] as? String
            ?? (params["turn"] as? [String: Any])?["id"] as? String
    }

    // MARK: - Private: async chain helpers

    /// After model/list completes, fire the stashed draft → thread/start.
    private func firePendingDraft() {
        guard let draft = pendingDraft else { return }
        do {
            if currentThreadID != nil {
                try startTurnFromDraft()
            } else {
                try startThread(draft: draft)
            }
        } catch {
            statusText = "failed to start thread: \(error)"
        }
    }

    /// Start a thread from stashed draft params.
    private func startThread(draft: DraftParams) throws {
        try startThread(
            cwd: draft.cwd,
            model: draft.model,
            effort: draft.effort,
            sandbox: draft.threadSandbox,
            approvalPolicy: draft.approvalPolicy
        )
    }

    /// After thread/started, fire the stashed draft → turn/start.
    private func firePendingTurn(threadID: String) {
        guard let draft = pendingDraft else { return }
        guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pendingDraft = nil
            statusText = "thread ready"
            return
        }
        do {
            try startTurn(
                threadID: threadID,
                text: draft.text,
                model: draft.model,
                effort: draft.effort,
                approvalPolicy: draft.approvalPolicy,
                sandboxPolicy: draft.turnSandbox
            )
        } catch {
            pendingDraft = nil
            statusText = "failed to start turn: \(error)"
        }
    }

    /// If thread exists, send turn directly from stashed draft.
    private func startTurnFromDraft() throws {
        guard let draft = pendingDraft, let threadID = currentThreadID else { return }
        guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pendingDraft = nil
            statusText = "thread ready"
            return
        }
        do {
            try startTurn(
                threadID: threadID,
                text: draft.text,
                model: draft.model,
                effort: draft.effort,
                approvalPolicy: draft.approvalPolicy,
                sandboxPolicy: draft.turnSandbox
            )
        } catch {
            pendingDraft = nil
            throw error
        }
    }

    // MARK: - Private: formatting

    private func formatRateLimits(_ params: [String: Any]?) -> String {
        RateLimitSnapshot.format(params: params)
    }

    private func updateModels(from result: [String: Any]?) {
        guard let result else { return }
        if let models = result["data"] as? [[String: Any]] ?? result["models"] as? [[String: Any]] {
            modelNames = models.compactMap { model in
                model["model"] as? String
                    ?? model["slug"] as? String
                    ?? model["id"] as? String
                    ?? model["name"] as? String
            }
        } else if let models = result["models"] as? [String] {
            modelNames = models
        }
        // Broadcast model list to relay connected clients
        let modelEvent = CodexAppServerEvent.notification(
            method: "model/list/done",
            params: ["models": modelNames]
        )
        onEventReceived?(modelEvent)
    }

    // MARK: - Session tracking

    private func recordSession(threadID: String, params: [String: Any]?) {
        let thread = params?["thread"] as? [String: Any] ?? params
        if !sessions.contains(where: { $0.sessionID == threadID }) {
            let newSession = RelaySessionInfoPayload(
                sessionID: threadID,
                cwd: thread?["cwd"] as? String,
                model: thread?["model"] as? String,
                effort: thread?["effort"] as? String,
                status: "active",
                createdAt: Date()
            )
            sessions.append(newSession)
        }
    }

    // MARK: - MacRelayRuntimeBridge

    func listSessions() -> [RelaySessionInfoPayload] {
        sessions
    }

    func stopSession() throws {
        pendingDraft = nil
        currentThreadID = nil
        latestTurnID = nil
        sessions.removeAll()
        print("[Log] Sessions stopped")
    }

    func clearCurrentThread() {
        pendingDraft = nil
        currentThreadID = nil
        latestTurnID = nil
        clearActiveTurn()
        print("[Log] Current thread cleared")
    }

    func selectSession(sessionID: String) throws {
        guard sessions.contains(where: { $0.sessionID == sessionID }) else {
            throw MacRelayBridgeError.sessionNotFound("Session \(sessionID) not found")
        }
        // Select the thread that should receive the next turn.
        // Do NOT restart the app-server or create a new thread here,
        // otherwise each selectSession would spawn a spurious new session.
        selectedSessionID = sessionID
        currentThreadID = sessionID
        latestTurnID = nil
        clearActiveTurn()
        statusText = "session.select sessionID=\(sessionID)"
    }
}
