import AgentClientCore
import Foundation

/// Live approval flow probe.
///
/// **Trigger:** readOnly sandbox + ask Codex to create a file.
/// Codex will issue `item/commandExecution/requestApproval`.
/// The probe then resolves the approval with `accept` and verifies
/// the file was created and `turn/completed` returns successfully.
///
/// **Quota impact:** this probe starts a real Codex thread and turn,
/// consuming model tokens.  It also creates a file in a temp directory.
///
/// **How to run:**
///     MACRELAY_RUN_LIVE_APPROVAL=1 .build/debug/RelayApprovalLiveProbe
///
/// Without the env var this probe skips and exits 0 immediately.
/// The fake `RelayRuntimeCommandDispatcherProbe` continues to cover the
/// approval wiring path without consuming quota.

enum ProbeError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let m): return m } }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ProbeError.failed(message) }
}

@MainActor
func runRelayApprovalLiveProbe() throws {
        guard ProcessInfo.processInfo.environment["MACRELAY_RUN_LIVE_APPROVAL"] == "1" else {
            print("RelayApprovalLiveProbe skipped (set MACRELAY_RUN_LIVE_APPROVAL=1 to run)")
            print("WARNING: this probe burns Codex quota and creates files. Use sparingly.")
            exit(0)
        }

        let cwd = FileManager.default.temporaryDirectory.appendingPathComponent("macrelay-approval-probe-\(UUID().uuidString.prefix(8))").path
        try FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: cwd) }

        let detection = CodexCLIDetector.detect()
        guard detection.isInstalled, let codexPath = detection.executablePath else {
            throw ProbeError.failed("Codex CLI not installed: \(detection.errorMessage ?? "unknown")")
        }
        print("codex=\(codexPath)")
        print("probe cwd=\(cwd)")

        let runtime = LiveCodexRuntimeBridge(codexPath: codexPath, cwd: cwd)
        defer { runtime.stop() }
        try runtime.start(cwd: cwd)

        let dispatcher = MacRelayRuntimeCommandDispatcher(runtime: runtime, defaultCWD: { cwd })
        let encoder = JSONEncoder()

        // Ensure readOnly sandbox so file creation triggers approval
        let settingsPayload = RelaySettingsUpdateCommandPayload(
            sessionID: runtime.currentThreadID ?? "thread-approval",
            model: nil,
            effort: "low",
            planMode: nil,
            permissionMode: "Read Only",
            approvalPolicy: "on-request",
            sandboxMode: "readOnly"
        )
        _ = try dispatcher.dispatch(commandType: .settingsUpdate, payloadData: encoder.encode(settingsPayload))
        try runtime.waitFor("thread/settings/update", timeout: 30)
        print("live approval settings applied (readOnly)")

        // Prompt Codex to create a file — this triggers approval in readOnly sandbox
        let filename = "approval-probe-\(UUID().uuidString.prefix(4)).txt"
        let turnPayload = RelayTurnStartCommandPayload(
            sessionID: runtime.currentThreadID ?? "thread-approval",
            input: "Create a new file called \(filename) with the single word approved inside it.",
            model: nil,
            effort: "low",
            planMode: false,
            permissionMode: "Read Only"
        )
        _ = try dispatcher.dispatch(commandType: .turnStart, payloadData: encoder.encode(turnPayload))

        // Wait for approval to appear, or turn to complete (with or without it)
        var sawApproval = false
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if !runtime.snapshot.pendingApprovals.isEmpty {
                sawApproval = true
                let (reqID, approval) = runtime.snapshot.pendingApprovals.first!
                print("live approval requested id=\(reqID) method=\(approval.method)")
                // Resolve with accept
                try runtime.resolveApproval(requestID: approval.requestID, decision: "accept")
                print("live approval accepted")
                break
            }
            if runtime.lastTurnCompleted { break }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
        }

        // Wait for turn to complete after resolution
        try runtime.waitFor("turn/completed", timeout: 120)
        let assistantText = runtime.snapshot.activeTurn?.assistantText ?? ""
        print("live assistantText length=\(assistantText.count)")

        // Verify file was created
        let filePath = "\(cwd)/\(filename)"
        let fileExists = FileManager.default.fileExists(atPath: filePath)
        if fileExists {
            let content = try? String(contentsOfFile: filePath, encoding: .utf8)
            print("live file created: \(filename) content=\(content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "nil")")
        }

        if sawApproval {
            print("live approval flow: approval was triggered and resolved")
        } else {
            print("live approval flow: no approval triggered (Codex may be allowed to write despite readOnly sandbox)")
            print("The fake RelayRuntimeCommandDispatcherProbe still covers approval.resolve wiring.")
        }

        // The presence of the file is the best indicator of success
        try expect(fileExists, "approval probe file should exist after acceptance")

    print("RelayApprovalLiveProbe passed approval=\(sawApproval) file=\(fileExists)")
}

try await runRelayApprovalLiveProbe()

// Reuse the live bridge from RelayCommandLiveProbe — trimmed to essentials.
@MainActor
final class LiveCodexRuntimeBridge: MacRelayRuntimeBridge {
    let client: CodexAppServerClient
    private let reducer = SessionStateReducer()
    private var pending: [Int: String] = [:]
    private var waiters: Set<String> = []
    private(set) var snapshot = SessionSnapshot()
    private(set) var currentThreadID: String?
    private(set) var lastTurnCompleted = false
    private(set) var lastError: String?

    init(codexPath: String, cwd: String) {
        self.client = CodexAppServerClient(codexCommand: codexPath, cwd: cwd)
        self.client.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    func start(cwd: String) throws {
        try client.start()
        let id = try client.request(method: "initialize", params: [
            "clientInfo": ["name": "relay-approval-live-probe", "title": "Relay Approval Live Probe", "version": "0.1.0"],
            "capabilities": ["experimentalApi": true]
        ])
        remember(id, method: "initialize")
        try waitFor("model/list", timeout: 30)
        let tid = try client.request(method: "thread/start", params: [
            "cwd": cwd, "sandbox": "read-only", "approvalPolicy": "on-request", "sessionStartSource": "startup"
        ])
        remember(tid, method: "thread/start")
        try waitFor("thread/start", timeout: 30)
    }

    func stop() { client.stop() }

    func enqueueDraft(cwd: String, text: String, model: String?, effort: String?, threadSandbox: String, turnSandbox: String, approvalPolicy: String) throws {
        guard let tid = currentThreadID else { throw ProbeError.failed("no thread") }
        lastTurnCompleted = false
        var params: [String: Any] = ["threadId": tid, "input": [["type": "text", "text": text]], "approvalPolicy": approvalPolicy, "sandboxPolicy": ["type": turnSandbox]]
        if let m = model { params["model"] = m }
        if let e = effort { params["effort"] = e }
        let id = try client.request(method: "turn/start", params: params)
        remember(id, method: "turn/start")
    }

    func updateSettings(model: String?, effort: String?, approvalPolicy: String?, sandboxPolicy: String?) throws -> Int {
        guard let tid = currentThreadID else { throw ProbeError.failed("no thread") }
        var params: [String: Any] = ["threadId": tid]
        if let m = model { params["model"] = m }
        if let e = effort { params["effort"] = e }
        if let a = approvalPolicy { params["approvalPolicy"] = a }
        if let s = sandboxPolicy { params["sandboxPolicy"] = ["type": s] }
        let id = try client.request(method: "thread/settings/update", params: params)
        remember(id, method: "thread/settings/update")
        return id
    }

    func resolveApproval(requestID: Int, decision: String) throws {
        try client.response(id: requestID, result: ["decision": decision])
        reducer.reduce(&snapshot, action: .approvalResolved(requestID: requestID, decision: decision))
    }

    func waitFor(_ method: String, timeout seconds: Int) throws {
        if method == "turn/completed", lastTurnCompleted { return }
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            if waiters.remove(method) != nil {
                if let lastError { throw ProbeError.failed(lastError) }
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        throw ProbeError.failed("timed out waiting for \(method)")
    }

    private func remember(_ id: Int, method: String) { pending[id] = method }
    private func signal(_ method: String) { waiters.insert(method) }

    private func handle(_ event: CodexAppServerEvent) {
        for action in reducer.actions(from: event) { reducer.reduce(&snapshot, action: action) }
        switch event {
        case let .response(id, result, error):
            let method = pending.removeValue(forKey: id) ?? "unknown"
            if let error { lastError = "\(method) response error: \(error)"; signal(method); return }
            if method == "initialize" {
                try? client.notification(method: "initialized")
                if let id = try? client.request(method: "model/list") { remember(id, method: "model/list") }
            }
            if method == "thread/start" { currentThreadID = result?["id"] as? String ?? (result?["thread"] as? [String: Any])?["id"] as? String ?? currentThreadID }
            signal(method)
        case let .notification(method, params):
            if method == "thread/started" { currentThreadID = params?["id"] as? String ?? (params?["thread"] as? [String: Any])?["id"] as? String ?? currentThreadID }
            if method == "turn/completed" { lastTurnCompleted = true; signal("turn/completed") }
            signal(method)
        case let .exit(code, _): lastError = "app-server exited code=\(code)"; waiters.formUnion(pending.values)
        default: break
        }
    }
}
