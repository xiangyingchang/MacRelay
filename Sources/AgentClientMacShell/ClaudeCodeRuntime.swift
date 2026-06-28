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
        // Check if `claude` CLI is on PATH (no zombie processes)
        guard let proc = try? Process.run(URL(fileURLWithPath: "/usr/bin/env"), arguments: ["which", "claude"]) else { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    // MARK: - Process management

    private var process: Process?
    private let stdoutBuffer = LineDelimitedJSONBuffer()
    private let stderrBuffer = LineDelimitedJSONBuffer()
    private var writer: JSONRPCWriter?
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var pendingDraft: DraftParams?
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
        case initialize, modelList, threadStart, turnStart, settingsUpdate
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
        statusText = "Fetching models..."
        // Start a lightweight init → model/list cycle to discover real models.
        // The app-server stays running so the next session doesn't need to re-init.
        do {
            if !isAppServerRunning {
                try startAppServer(cwd: FileManager.default.currentDirectoryPath)
            }
            if !isInitialized {
                try initialize()
            }
        } catch {
            statusText = "model fetch failed: \(error)"
        }
    }

    override func startAppServer(cwd: String) throws {
        guard cliInstalled else {
            statusText = "Claude Code CLI not found"
            throw MacRelayBridgeError.sessionNotFound("Claude Code CLI not found. Install: npm install -g @anthropic-ai/claude-code")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["npx", "claude-app-server"]
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)

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
                self.statusText = "stderr: \(line.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        }

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.process = nil
                self?.isAppServerRunning = false
                self?.statusText = "Claude app-server exited"
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

        if !isAppServerRunning {
            try startAppServer(cwd: cwd)
        }
        if !isInitialized {
            if !isInitializing { try initialize() }
            statusText = "Initializing → will auto-send..."
        } else if currentThreadID == nil {
            try startThread(draft: pendingDraft!)
        } else {
            try startTurnFromDraft()
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
        let id = nextId; nextId += 1
        var params: [String: Any] = ["threadId": currentThreadID ?? ""]
        if let model { params["model"] = model }
        if let effort { params["effort"] = effort }
        try sendRequest(id: id, method: "thread/settings/update", params: params)
        return id
    }

    override func selectSession(sessionID: String) throws {
        guard sessions.contains(where: { $0.sessionID == sessionID }) else {
            throw MacRelayBridgeError.sessionNotFound("Session \(sessionID) not found")
        }
        selectedSessionID = sessionID
        statusText = "session.select sessionID=\(sessionID)"
    }

    // MARK: - Private

    private func startThread(draft: DraftParams) throws {
        let id = nextId; nextId += 1
        try sendRequest(id: id, method: "thread/start", params: [
            "cwd": draft.cwd,
            "sandbox": draft.threadSandbox,
            "approvalPolicy": draft.approvalPolicy,
            "sessionStartSource": "startup"
        ])
        pendingRequests[id] = PendingRequest(kind: .threadStart, createdAt: Date())
    }

    private func startTurnFromDraft() throws {
        guard let draft = pendingDraft, let threadID = currentThreadID else { return }
        let id = nextId; nextId += 1
        try sendRequest(id: id, method: "turn/start", params: [
            "threadId": threadID,
            "input": [["type": "text", "text": draft.text]]
        ])
        pendingRequests[id] = PendingRequest(kind: .turnStart, createdAt: Date())
    }

    private func sendRequest(id: Int, method: String, params: Any) throws {
        guard let writer else { throw CodexAppServerClientError.notStarted }
        try writer.request(id: id, method: method, params: params)
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let event: CodexAppServerEvent

        if json["method"] != nil, json["id"] == nil {
            // Notification or server request
            if let id = json["id"] as? Int {
                // Server request (e.g. approval)
                let method = json["method"] as? String ?? ""
                let params = json["params"] as? [String: Any]
                event = CodexAppServerEvent.serverRequest(id: id, method: method, params: params)
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

        // Forward event to relay and reduce into snapshot (same as CodexRuntime)
        onEventReceived?(event)
        apply(reducer.actions(from: event))
    }

    private func handleResponse(id: Int, result: [String: Any]?, error: Any?) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        guard error == nil else {
            statusText = "response \(id) error: \(error!)"
            isInitializing = false
            return
        }

        switch pending.kind {
        case .initialize:
            statusText = "initialized → model/list"
            try? writer?.notification(method: "initialized", params: [:])
            let mid = nextId; nextId += 1
            try? sendRequest(id: mid, method: "model/list", params: [:])
            pendingRequests[mid] = PendingRequest(kind: .modelList, createdAt: Date())

        case .modelList:
            statusText = "model/list received"
            let models = result?["models"] as? [[String: Any]] ?? []
            modelNames = models.compactMap { $0["id"] as? String }
            isInitialized = true
            isInitializing = false
            firePendingDraft()

        case .threadStart:
            statusText = "thread/start response"
            // claude-app-server returns thread_id (snake_case), Codex returns id
            if let threadID = result?["thread_id"] as? String
                ?? result?["id"] as? String
                ?? (result?["thread"] as? [String: Any])?["id"] as? String {
                if currentThreadID == nil {
                    currentThreadID = threadID
                    firePendingTurn(threadID: threadID)
                }
            }

        case .turnStart:
            statusText = "turn active"
            if let turnID = result?["id"] as? String
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
            let turnID = params?["id"] as? String ?? (params?["turn"] as? [String: Any])?["id"] as? String
            if let turnID { latestTurnID = turnID }
            if let threadID = currentThreadID,
               let idx = sessions.firstIndex(where: { $0.sessionID == threadID }),
               (sessions[idx].title ?? "").isEmpty,
               let draft = pendingDraft, !draft.text.isEmpty {
                sessions[idx].title = draft.text
            }

        case "turn/completed":
            statusText = "turn completed"
            pendingDraft = nil

        case "item/agentMessage/delta":
            break // Reducer handles text append

        default:
            statusText = "notification: \(method)"
        }
    }

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

    private func firePendingTurn(threadID: String) {
        guard let draft = pendingDraft else { return }
        do {
            let id = nextId; nextId += 1
            try sendRequest(id: id, method: "turn/start", params: [
                "threadId": threadID,
                "input": [["type": "text", "text": draft.text]]
            ])
            pendingRequests[id] = PendingRequest(kind: .turnStart, createdAt: Date())
        } catch {
            pendingDraft = nil
            statusText = "failed to start turn: \(error)"
        }
    }

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

    /// Reduce event actions into the local snapshot (mirrors CodexRuntime.apply)
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
