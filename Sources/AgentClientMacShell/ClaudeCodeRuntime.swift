import AgentClientCore
import Foundation

// MARK: - ClaudeCodeRuntime

/// Manages a `npx claude-app-server` process. The claude-app-server npm
/// package implements the same JSON-RPC 2.0 protocol as Codex CLI's
/// app-server, so the event handling chain (SessionStateReducer) is shared.
@MainActor
final class ClaudeCodeRuntime: AgentRuntime {
    override init() { super.init(); statusText = "Claude Code ready" }

    override var cliInstalled: Bool {
        // Cache result so it doesn't spawn a process on every access
        _cliInstalled
    }
    private var _cliInstalled: Bool = {
        // Run Process on a background queue so waitUntilExit's nested run loop
        // doesn't collide with SwiftUI/AttributeGraph on the main thread during
        // @MainActor init (especially during window restoration).
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        DispatchQueue.global().async {
            if let proc = try? Process.run(URL(fileURLWithPath: "/usr/bin/env"), arguments: ["which", "claude"]) {
                proc.waitUntilExit()
                result = proc.terminationStatus == 0
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }()

    // MARK: - Process management

    private var process: Process?
    private let stdoutBuffer = LineDelimitedJSONBuffer()
    private let stderrBuffer = LineDelimitedJSONBuffer()
    private var writer: JSONRPCWriter?
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var pendingDraft: DraftParams?
    private var lastStderr = ""
    private var pendingResumeThreadID: String?
    private var restoredSessionIDs = Set<String>()
    private let reducer = SessionStateReducer()
    private var nextId = 1

    private struct PendingRequest {
        let kind: PendingRequestKind
        let createdAt: Date
    }

    private struct DraftParams {
        let cwd: String
        let text: String
        let model: String?
        let effort: String?
        let threadSandbox: String
        let turnSandbox: String
        let approvalPolicy: String
    }

    private enum PendingRequestKind: String {
        case initialize, modelList, threadStart, threadResume, turnStart, settingsUpdate
    }

    var isProcessingTurn: Bool { pendingDraft != nil }

    override func clearCurrentThread() {
        pendingDraft = nil
        currentThreadID = nil
        latestTurnID = nil
        statusText = "Current thread cleared"
    }

    override func refreshDetection() {
        guard cliInstalled else {
            statusText = "Claude Code CLI not found"
            return
        }
        statusText = "Claude Code ready"
        // Read models from Claude Code settings instead of querying model/list,
        // because claude-app-server (npm) returns hardcoded models that don't
        // reflect the user's actual provider configuration (e.g. DeepSeek).
        modelNames = ClaudeCodeSettingsReader.readModelNames()
    }

    override func startAppServer(cwd: String) throws {
        guard cliInstalled else {
            statusText = "Claude Code CLI not found"
            throw MacRelayBridgeError.runtimeUnavailable("Claude Code CLI not found. Install: npm install -g @anthropic-ai/claude-code")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["npx", "--yes", "claude-app-server"]
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        lastStderr = ""

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        self.writer = JSONRPCWriter(fileHandle: stdinPipe.fileHandleForWriting)
        self.process = proc

        // Read stdout (NDJSON)
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            Task { @MainActor in
                self.stdoutBuffer.append(data)
                while let line = self.stdoutBuffer.nextLine() {
                    self.handleLine(line)
                }
            }
        }

        // Read stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, let line = String(data: data, encoding: .utf8), !line.isEmpty else { return }
            Task { @MainActor in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.lastStderr = trimmed
                self.addStep(.stderr, detail: trimmed)
                self.statusText = "stderr: \(trimmed)"
            }
        }

        proc.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                if self?.pendingDraft != nil {
                    let detail = self?.lastStderr.isEmpty == false ? " \(self?.lastStderr ?? "")" : ""
                    self?.failPendingDraft("Claude app-server exited before the turn could start (code \(proc.terminationStatus)).\(detail)")
                }
                self?.process = nil
                self?.isAppServerRunning = false
                if self?.statusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    self?.statusText = "Claude app-server exited"
                }
            }
        }

        try proc.run()
        isAppServerRunning = true
        statusText = "Claude app-server started"
    }

    override func stopAppServer() {
        process?.terminate()
        process = nil
        writer = nil
        isAppServerRunning = false
        isInitialized = false
        currentThreadID = nil
        latestTurnID = nil
        pendingRequests.removeAll()
        pendingDraft = nil
        statusText = "Claude app-server stopped"
    }

    override func initialize() throws -> Int {
        guard !isInitializing else { return 0 }
        let id = nextId; nextId += 1
        try sendRequest(id: id, method: "initialize", params: [
            "protocolVersion": "1",
            "clientInfo": ["name": "agent-client-mac-shell", "version": "0.1.0"],
            "capabilities": [:]
        ])
        pendingRequests[id] = PendingRequest(kind: .initialize, createdAt: Date())
        isInitializing = true
        statusText = "initialize requested"
        return id
    }

    override func enqueueDraft(
        cwd: String, text: String, model: String?, effort: String?,
        threadSandbox: String, turnSandbox: String, approvalPolicy: String
    ) throws {
        guard !isProcessingTurn else {
            throw MacRelayBridgeError.turnInProgress("previous turn still processing — wait for completion")
        }
        pendingDraft = DraftParams(
            cwd: cwd, text: text, model: model, effort: effort,
            threadSandbox: threadSandbox, turnSandbox: turnSandbox,
            approvalPolicy: approvalPolicy
        )
        latestTurnID = nil
        resetSteps()

        if !isAppServerRunning {
            try startAppServer(cwd: cwd)
        }
        if !isInitialized {
            if !isInitializing { _ = try initialize() }
            statusText = "Initializing → will auto-send..."
        } else if currentThreadID == nil {
            try startThread(draft: pendingDraft!)
        } else if let pendingResumeThreadID {
            try resumeThread(threadID: pendingResumeThreadID)
        } else {
            // Wrap in do/catch so pendingDraft is cleared on error,
            // preventing "previous turn still processing" lockout on
            // subsequent enqueueDraft calls.
            do {
                try startTurnFromDraft()
            } catch {
                pendingDraft = nil
                throw error
            }
        }
    }

    override func resolveApproval(requestID: Int, decision: String) throws {
        guard let writer else { return }
        try writer.sendResponse(id: requestID, result: ["decision": decision])
        statusText = "approval \(decision)"
    }

    override func updateSettings(
        model: String?, effort: String?, approvalPolicy: String?,
        sandboxPolicy: String?
    ) throws -> Int {
        // claude-app-server 1.0.x has no thread/settings/update method. Model
        // is applied on the next turn/start, so settings changes are local.
        statusText = "Claude settings staged"
        return 0
    }

    override func selectSession(sessionID: String) throws {
        guard sessions.contains(where: { $0.sessionID == sessionID }) else {
            throw MacRelayBridgeError.sessionNotFound("Session \(sessionID) not found")
        }
        selectedSessionID = sessionID
        currentThreadID = sessionID
        pendingResumeThreadID = restoredSessionIDs.contains(sessionID) ? sessionID : nil
        latestTurnID = nil
        statusText = "session.select sessionID=\(sessionID)"
    }

    override func rememberSession(sessionID: String, cwd: String?, title: String?, status: String?) {
        if !sessions.contains(where: { $0.sessionID == sessionID }) {
            sessions.append(RelaySessionInfoPayload(
                sessionID: sessionID,
                cwd: cwd,
                model: nil,
                effort: nil,
                status: status ?? "saved",
                createdAt: nil,
                title: title
            ))
        }
        restoredSessionIDs.insert(sessionID)
    }

    // MARK: - Private

    private func startThread(draft: DraftParams) throws {
        let id = nextId; nextId += 1
        try sendRequest(id: id, method: "thread/start", params: [
            "cwd": draft.cwd,
            "permission_mode": claudePermissionMode(for: draft),
            "sessionStartSource": "startup"
        ])
        pendingRequests[id] = PendingRequest(kind: .threadStart, createdAt: Date())
    }

    private func resumeThread(threadID: String) throws {
        let id = nextId; nextId += 1
        try sendRequest(id: id, method: "thread/resume", params: [
            "thread_id": threadID
        ])
        pendingRequests[id] = PendingRequest(kind: .threadResume, createdAt: Date())
        statusText = "thread/resume requested"
    }

    private func startTurnFromDraft() throws {
        guard let draft = pendingDraft, let threadID = currentThreadID else {
            print("[CCRuntime] startTurnFromDraft: pendingDraft=\(pendingDraft != nil) currentThreadID=\(currentThreadID ?? "nil") — bailing")
            pendingDraft = nil
            return
        }
        guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pendingDraft = nil
            statusText = "thread ready"
            return
        }
        let id = nextId; nextId += 1
        var params: [String: Any] = [
            "thread_id": threadID,
            "content": draft.text
        ]
        if let model = draft.model, !model.isEmpty {
            params["model"] = model
        }
        try sendRequest(id: id, method: "turn/start", params: params)
        pendingRequests[id] = PendingRequest(kind: .turnStart, createdAt: Date())
    }

    private func claudePermissionMode(for draft: DraftParams) -> String {
        if draft.approvalPolicy == "never" || draft.threadSandbox == "danger-full-access" {
            return "bypassPermissions"
        }
        if draft.threadSandbox == "workspace-write" {
            return "acceptEdits"
        }
        return "default"
    }

    private func sendRequest(id: Int, method: String, params: Any) throws {
        guard let writer else { throw CodexAppServerClientError.notStarted }
        try writer.request(id: id, method: method, params: params)
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let method = json["method"] as? String ?? ""
        let isNotification = json["id"] == nil
        // Log key event types for streaming debugging
        if isNotification, ["turn/started", "item/agentMessage/delta", "item/progress", "turn/completed"].contains(method) {
            let p = json["params"] as? [String: Any]
            print("[CCRuntime] event: \(method) id=\(json["id"] ?? "nil") turn_id=\(p?["turn_id"] ?? p?["id"] ?? "nil")")
        }

        let event: CodexAppServerEvent

        if json["method"] != nil, json["id"] == nil {
            // Notification or server request
            if let id = json["id"] as? Int {
                // Server request (e.g. approval)
                let method = json["method"] as? String ?? ""
                let params = json["params"] as? [String: Any]
                event = CodexAppServerEvent.serverRequest(id: id, method: method, params: params)
                if method.contains("requestApproval") {
                    addStep(.approval, detail: params?["command"] as? String ?? params?["reason"] as? String, status: .active)
                }
            } else {
                // Notification
                let method = json["method"] as? String ?? ""
                let params = json["params"] as? [String: Any]
                event = CodexAppServerEvent.notification(method: method, params: params)
                handleNotification(method: method, params: params)
            }
        } else if json["id"] != nil {
            // Response
            let id = json["id"] as? Int ?? 0
            let result = json["result"] as? [String: Any]
            let error = json["error"]
            event = CodexAppServerEvent.response(id: id, result: result, error: error)
            handleResponse(id: id, result: result, error: error)
        } else {
            return
        }

        let relayEvent = normalizedEvent(event)
        // Forward event to relay and reduce into snapshot (same as CodexRuntime)
        onEventReceived?(relayEvent)
        apply(reducer.actions(from: relayEvent))
    }

    private func handleResponse(id: Int, result: [String: Any]?, error: Any?) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        if let error {
            statusText = "response \(id) error: \(error)"
            isInitializing = false
            updateLastStep(status: .failed)
            addStep(.error, detail: "\(error)", status: .failed)
            if pending.kind == .threadStart || pending.kind == .threadResume || pending.kind == .turnStart || pending.kind == .initialize || pending.kind == .modelList {
                pendingDraft = nil
            }
            let errorDict = error as? [String: Any]
            apply(.error(params: [
                "error": [
                    "message": errorDict?["message"] as? String ?? "\(error)",
                    "code": errorDict?["code"] as? String ?? ""
                ]
            ]))
            return
        }

        switch pending.kind {
        case .initialize:
            statusText = "initialized → model/list"
            addStep(.initialize)
            try? writer?.notification(method: "initialized", params: [:])
            let mid = nextId; nextId += 1
            try? sendRequest(id: mid, method: "model/list", params: [:])
            pendingRequests[mid] = PendingRequest(kind: .modelList, createdAt: Date())

        case .modelList:
            statusText = "model/list received"
            addStep(.modelList)
            // Don't overwrite models from settings with claude-app-server's hardcoded list
            if modelNames.isEmpty {
                let models = result?["models"] as? [[String: Any]] ?? []
                modelNames = models.compactMap { $0["id"] as? String }
            }
            isInitialized = true
            isInitializing = false
            firePendingDraft()

        case .threadStart:
            statusText = "thread/start response"
            addStep(.threadStart)
            // claude-app-server returns thread_id (snake_case), Codex returns id
            if let threadID = result?["thread_id"] as? String
                ?? result?["id"] as? String
                ?? (result?["thread"] as? [String: Any])?["id"] as? String {
                if currentThreadID == nil {
                    currentThreadID = threadID
                    recordSession(threadID: threadID, params: result)
                    if let draft = pendingDraft, !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let idx = sessions.firstIndex(where: { $0.sessionID == threadID }) {
                            sessions[idx].title = draft.text
                        }
                        firePendingTurn(threadID: threadID)
                    } else {
                        pendingDraft = nil
                        statusText = "thread ready"
                    }
                    onThreadStarted?(threadID)
                }
            }

        case .threadResume:
            statusText = "thread/resume response"
            addStep(.threadStart, detail: "resume", status: .active)
            pendingResumeThreadID = nil
            if let threadID = result?["thread_id"] as? String
                ?? result?["id"] as? String
                ?? (result?["thread"] as? [String: Any])?["id"] as? String {
                currentThreadID = threadID
                restoredSessionIDs.remove(threadID)
            }
            if pendingDraft != nil {
                do {
                    try startTurnFromDraft()
                } catch {
                    failPendingDraft("Failed to start turn after resume: \(error)")
                }
            }

        case .turnStart:
            statusText = "turn active"
            addStep(.turnStart, status: .active)
            if let turnID = result?["turn_id"] as? String
                ?? result?["id"] as? String
                ?? (result?["turn"] as? [String: Any])?["id"] as? String {
                latestTurnID = turnID
            }

        case .settingsUpdate:
            statusText = "settings updated"
        }
    }

    private func handleNotification(method: String, params: [String: Any]?) {
        switch method {
        case "thread/started":
            statusText = "thread started"
            if let threadID = params?["id"] as? String
                ?? params?["thread_id"] as? String
                ?? (params?["thread"] as? [String: Any])?["id"] as? String {
                currentThreadID = threadID
                recordSession(threadID: threadID, params: params)
                if let draft = pendingDraft, !draft.text.isEmpty {
                    if let idx = sessions.firstIndex(where: { $0.sessionID == threadID }) {
                        sessions[idx].title = draft.text
                    }
                    firePendingTurn(threadID: threadID)
                }
                pendingDraft = nil
                onThreadStarted?(threadID)
            }

        case "turn/started":
            let turnID = params?["turn_id"] as? String ?? params?["id"] as? String ?? (params?["turn"] as? [String: Any])?["id"] as? String
            if let turnID { latestTurnID = turnID }
            addStep(.assistantResponse, status: .active)
            if let threadID = currentThreadID,
               let idx = sessions.firstIndex(where: { $0.sessionID == threadID }),
               (sessions[idx].title ?? "").isEmpty,
               let draft = pendingDraft, !draft.text.isEmpty {
                sessions[idx].title = draft.text
            }

        case "turn/completed":
            statusText = "turn completed"
            updateLastStep(status: .completed)
            addStep(.turnCompleted)
            pendingDraft = nil

        case "turn/error":
            statusText = "turn error"
            updateLastStep(status: .failed)
            addStep(.error, detail: params?["error"] as? String, status: .failed)
            pendingDraft = nil

        case "item/agentMessage/delta":
            break // Reducer handles text append

        case "item/progress":
            break // normalizedEvent maps this to item/agentMessage/delta

        case "error":
            statusText = "error"
            addStep(.error, detail: params?["error"] as? String, status: .failed)

        default:
            statusText = "notification: \(method)"
        }
    }

    private func normalizedEvent(_ event: CodexAppServerEvent) -> CodexAppServerEvent {
        guard case let .notification(method, params) = event else { return event }
        switch method {
        case "turn/started":
            var next = params ?? [:]
            let turnID = next["turn_id"] as? String
                ?? next["id"] as? String
                ?? (next["turn"] as? [String: Any])?["id"] as? String
            if let turnID {
                next["turn"] = ["id": turnID]
            }
            if next["input"] == nil, let draft = pendingDraft {
                next["input"] = draft.text
            }
            return .notification(method: method, params: next)

        case "item/progress":
            let delta = params?["delta"] as? [String: Any]
            let text = delta?["text"] as? String ?? params?["text"] as? String ?? ""
            return .notification(method: "item/agentMessage/delta", params: ["delta": text])

        case "turn/error":
            let message = params?["error"] as? String ?? "Claude turn failed"
            return .notification(method: "error", params: ["error": ["message": message]])

        default:
            return event
        }
    }

    private func firePendingDraft() {
        guard let draft = pendingDraft else { return }
        do {
            if let pendingResumeThreadID {
                try resumeThread(threadID: pendingResumeThreadID)
            } else if currentThreadID != nil {
                try startTurnFromDraft()
            } else {
                try startThread(draft: draft)
            }
        } catch {
            failPendingDraft("Failed to start thread: \(error)")
        }
    }

    private func firePendingTurn(threadID: String) {
        guard let draft = pendingDraft else { return }
        guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pendingDraft = nil
            statusText = "thread ready"
            return
        }
        do {
            let id = nextId; nextId += 1
            var params: [String: Any] = [
                "thread_id": threadID,
                "content": draft.text
            ]
            if let model = draft.model, !model.isEmpty {
                params["model"] = model
            }
            try sendRequest(id: id, method: "turn/start", params: params)
            pendingRequests[id] = PendingRequest(kind: .turnStart, createdAt: Date())
        } catch {
            failPendingDraft("Failed to start turn: \(error)")
        }
    }

    private func failPendingDraft(_ message: String) {
        pendingDraft = nil
        statusText = message
        apply(.error(params: [
            "error": [
                "message": message,
                "codexErrorInfo": "runtime_start_failed"
            ]
        ]))
    }

    private func recordSession(threadID: String, params: [String: Any]?) {
        let thread = params?["thread"] as? [String: Any] ?? params
        restoredSessionIDs.remove(threadID)
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

    /// Reduce event actions into the local snapshot (mirrors CodexRuntime.apply)
    private func apply(_ actions: [SessionReducerAction]) {
        guard !actions.isEmpty else { return }
        var nextSnapshot = snapshot
        for action in actions {
            reducer.reduce(&nextSnapshot, action: action)
            // Capture file change events as steps
            if case let .fileChangeUpdated(change) = action {
                let path = change.path ?? change.itemID ?? "unknown"
                let kind = change.changeKind ?? "changed"
                addStep(.fileChange, detail: "\(kind) \(path)")
            }
        }
        snapshot = nextSnapshot
    }

    private func apply(_ action: SessionReducerAction) {
        apply([action])
    }
}

// MARK: - Helpers

private struct JSONRPCWriter {
    let fileHandle: FileHandle
    private let encoder = JSONEncoder()

    func request(id: Int, method: String, params: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ] as [String: Any])
        var line = String(data: data, encoding: .utf8)!
        line += "\n"
        try fileHandle.write(contentsOf: Data(line.utf8))
    }

    func notification(method: String, params: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ] as [String: Any])
        var line = String(data: data, encoding: .utf8)!
        line += "\n"
        try fileHandle.write(contentsOf: Data(line.utf8))
    }

    func sendResponse(id: Int, result: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ] as [String: Any])
        var line = String(data: data, encoding: .utf8)!
        line += "\n"
        try fileHandle.write(contentsOf: Data(line.utf8))
    }
}

// MARK: - Claude Code Settings Reader

/// Reads `~/.claude/settings.json` to discover the user's actual model
/// configuration (provider-agnostic — could be Anthropic, DeepSeek, etc.).
enum ClaudeCodeSettingsReader {
    static func readModelNames() -> [String] {
        let paths = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json").path,
        ]
        return readModelNames(paths: paths)
    }

    static func readModelNames(paths: [String]) -> [String] {
        for path in paths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            var models: [String] = []
            let env = json["env"] as? [String: Any] ?? [:]

            // Primary model (ANTHROPIC_MODEL)
            if let model = env["ANTHROPIC_MODEL"] as? String, !model.isEmpty {
                models.append(Self.modelAlias(model))
            }

            // Model defaults
            for key in ["ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_SMALL_FAST_MODEL"] {
                if let model = env[key] as? String, !model.isEmpty, !models.contains(model) {
                    let mapped = Self.modelAlias(model)
                    if !models.contains(mapped) { models.append(mapped) }
                }
            }

            // Top-level aliases are Claude Code UI defaults. When provider env
            // models exist (DeepSeek, etc.), those are the real model IDs.
            if models.isEmpty, let model = json["model"] as? String {
                let mapped = Self.modelAlias(model)
                if !models.contains(mapped) { models.append(mapped) }
            }

            if !models.isEmpty { return models }
        }
        return ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5"] // fallback
    }

    private static func modelAlias(_ alias: String) -> String {
        switch alias.lowercased() {
        case "opus": return "claude-opus-4-6"
        case "sonnet": return "claude-sonnet-4-6"
        case "haiku": return "claude-haiku-4-5"
        default: return alias
        }
    }
}

private class LineDelimitedJSONBuffer {
    private var buffer = ""

    func append(_ data: Data) {
        guard let str = String(data: data, encoding: .utf8) else { return }
        buffer += str
    }

    func nextLine() -> String? {
        guard let range = buffer.range(of: "\n") else { return nil }
        let line = String(buffer[buffer.startIndex..<range.lowerBound])
        buffer = String(buffer[range.upperBound...])
        return line.isEmpty ? nil : line
    }
}
