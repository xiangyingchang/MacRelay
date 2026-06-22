import AgentClientCore
import Foundation

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
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    func start(cwd: String) throws {
        try client.start()
        let initializeID = try client.request(method: "initialize", params: [
            "clientInfo": [
                "name": "relay-command-live-probe",
                "title": "Relay Command Live Probe",
                "version": "0.1.0"
            ],
            "capabilities": ["experimentalApi": true]
        ])
        remember(initializeID, method: "initialize")
        try waitFor("model/list", timeout: 30)

        let threadID = try client.request(method: "thread/start", params: [
            "cwd": cwd,
            "sandbox": "read-only",
            "approvalPolicy": "on-request",
            "sessionStartSource": "startup"
        ])
        remember(threadID, method: "thread/start")
        try waitFor("thread/start", timeout: 30)
        if currentThreadID == nil {
            throw ProbeError.failed("thread/start completed without thread id")
        }
    }

    func stop() {
        client.stop()
    }

    func enqueueDraft(
        cwd: String,
        text: String,
        model: String?,
        effort: String?,
        threadSandbox: String,
        turnSandbox: String,
        approvalPolicy: String
    ) throws {
        guard let currentThreadID else {
            throw ProbeError.failed("turn requested before thread/start")
        }
        lastTurnCompleted = false
        var params: [String: Any] = [
            "threadId": currentThreadID,
            "input": [["type": "text", "text": text]],
            "approvalPolicy": approvalPolicy,
            "sandboxPolicy": ["type": turnSandbox]
        ]
        if let model { params["model"] = model }
        if let effort { params["effort"] = effort }
        let id = try client.request(method: "turn/start", params: params)
        remember(id, method: "turn/start")
    }

    func updateSettings(model: String?, effort: String?, approvalPolicy: String?, sandboxPolicy: String?) throws -> Int {
        guard let currentThreadID else {
            throw ProbeError.failed("settings update requested before thread/start")
        }
        var params: [String: Any] = ["threadId": currentThreadID]
        if let model { params["model"] = model }
        if let effort { params["effort"] = effort }
        if let approvalPolicy { params["approvalPolicy"] = approvalPolicy }
        if let sandboxPolicy { params["sandboxPolicy"] = ["type": sandboxPolicy] }
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
                if let lastError {
                    throw ProbeError.failed(lastError)
                }
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        throw ProbeError.failed("timed out waiting for \(method)")
    }

    private func remember(_ id: Int, method: String) {
        pending[id] = method
    }

    private func signal(_ method: String) {
        waiters.insert(method)
    }

    private func handle(_ event: CodexAppServerEvent) {
        for action in reducer.actions(from: event) {
            reducer.reduce(&snapshot, action: action)
        }

        switch event {
        case let .response(id, result, error):
            let method = pending.removeValue(forKey: id) ?? "unknown"
            if let error {
                lastError = "\(method) response error: \(error)"
                signal(method)
                return
            }
            print("live response method=\(method) keys=\((result ?? [:]).keys.sorted())")
            if method == "initialize" {
                try? client.notification(method: "initialized")
                if let modelID = try? client.request(method: "model/list") {
                    remember(modelID, method: "model/list")
                }
            }
            if method == "thread/start" {
                currentThreadID = result?["id"] as? String ?? (result?["thread"] as? [String: Any])?["id"] as? String ?? currentThreadID
            }
            signal(method)

        case let .notification(method, params):
            if method == "thread/started" {
                currentThreadID = params?["id"] as? String ?? (params?["thread"] as? [String: Any])?["id"] as? String ?? currentThreadID
            }
            if method == "thread/settings/updated" {
                signal("thread/settings/updated")
            }
            if method == "turn/completed" {
                lastTurnCompleted = true
                signal("turn/completed")
            }
            print("live notification method=\(method)")

        case let .serverRequest(id, method, _):
            print("live serverRequest id=\(id) method=\(method)")

        case let .stderr(line):
            print("live stderr \(line)")

        case let .raw(line):
            print("live raw \(line)")

        case let .exit(code, _):
            lastError = "app-server exited code=\(code)"
            waiters.formUnion(pending.values)
        }
    }
}

enum ProbeError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw ProbeError.failed(message)
    }
}

@main
struct RelayCommandLiveProbe {
    @MainActor
    static func main() throws {
        guard ProcessInfo.processInfo.environment["MACRELAY_RUN_LIVE_CODEX"] == "1" else {
            print("RelayCommandLiveProbe skipped (set MACRELAY_RUN_LIVE_CODEX=1 to run)")
            exit(0)
        }

        let cwd = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
        let detection = CodexCLIDetector.detect()
        guard detection.isInstalled, let codexPath = detection.executablePath else {
            throw ProbeError.failed("Codex CLI not installed: \(detection.errorMessage ?? "unknown")")
        }
        print("codex=\(codexPath)")
        print("version=\(detection.version ?? "unknown")")
        print("live cwd=\(cwd)")

        let runtime = LiveCodexRuntimeBridge(codexPath: codexPath, cwd: cwd)
        defer { runtime.stop() }
        try runtime.start(cwd: cwd)

        let dispatcher = MacRelayRuntimeCommandDispatcher(runtime: runtime, defaultCWD: { cwd })
        let encoder = JSONEncoder()

        let settingsPayload = RelaySettingsUpdateCommandPayload(
            sessionID: runtime.currentThreadID ?? "thread-live",
            model: nil,
            effort: "low",
            planMode: nil,
            permissionMode: "Read Only",
            approvalPolicy: "on-request",
            sandboxMode: "readOnly"
        )
        let settingsResult = try dispatcher.dispatch(commandType: .settingsUpdate, payloadData: encoder.encode(settingsPayload))
        try expect(settingsResult == .dispatched("session.settings.update"), "settings dispatch result mismatch")
        try runtime.waitFor("thread/settings/update", timeout: 30)
        print("live command session.settings.update passed")

        let turnPayload = RelayTurnStartCommandPayload(
            sessionID: runtime.currentThreadID ?? "thread-live",
            input: "Reply exactly: ok",
            model: nil,
            effort: "low",
            planMode: false,
            permissionMode: "Read Only"
        )
        let turnResult = try dispatcher.dispatch(commandType: .turnStart, payloadData: encoder.encode(turnPayload))
        try expect(turnResult == .dispatched("session.turn.start"), "turn dispatch result mismatch")
        try runtime.waitFor("turn/completed", timeout: 120)
        let assistantText = runtime.snapshot.activeTurn?.assistantText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        print("live assistantText=\(assistantText)")
        try expect(!assistantText.isEmpty, "assistant text should not be empty")
        try expect(assistantText.lowercased().contains("ok"), "assistant text should contain ok")
        print("live command session.turn.start passed")
        print("approval.resolve live gap: not triggered in tiny read-only prompt; fake dispatcher probe remains coverage for response wiring")
        print("RelayCommandLiveProbe passed")
    }
}
