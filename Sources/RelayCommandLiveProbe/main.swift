import Foundation

#if os(macOS)
import AgentClientCore

enum ProbeError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let m): return m } }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ProbeError.failed(message) }
}

@MainActor
final class LiveCodexRuntimeBridge: MacRelayRuntimeBridge {
    let client: CodexAppServerClient
    private let reducer = SessionStateReducer()
    private var pending: [Int: String] = [:]
    private var waiters: Set<String> = []
    private(set) var snapshot = SessionSnapshot()
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
            "clientInfo": ["name": "cmd-probe", "title": "Cmd Probe", "version": "0.1.0"]])
        pending[id] = "initialize"
    }

    func stop() { client.stop() }

    func waitFor(_ method: String, timeout seconds: Int) throws {
        if method == "turn/completed", lastTurnCompleted { return }
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline { if lastTurnCompleted { return }; Thread.sleep(forTimeInterval: 0.1) }
    }

    private func handle(_ event: CodexAppServerEvent) {
        switch event {
        case let .response(id, result, error):
            guard let method = pending.removeValue(forKey: id) else { return }
            if method == "initialize" {
                try? client.notification(method: "initialized")
                do { let mid = try client.request(method: "settings/update", params: ["settings": ["model": "test"]]); pending[mid] = "settings/update" }
                catch { lastError = "\(error)" }
            } else if method == "settings/update" {
                do { let tid = try client.request(method: "thread/start", params: ["cwd": "/tmp", "sandbox": "read-only", "approvalPolicy": "on-request", "sessionStartSource": "startup"]); pending[tid] = "thread/start" }
                catch { lastError = "\(error)" }
            } else if method == "thread/start" {
                do { let tid = try client.request(method: "turn/start", params: ["threadId": currentThreadID ?? (result?["id"] as? String ?? ""), "input": [["type": "text", "text": "Reply exactly: ok"]], "approvalPolicy": "on-request"]); pending[tid] = "turn/start" }
                catch { lastError = "\(error)" }
            }
        case let .notification(method, params):
            if method == "item/agentMessage/delta", let delta = params?["delta"] as? String, delta.contains("ok") {
                lastTurnCompleted = true; waiters.formUnion(pending.values)
            }
            if method == "turn/completed" { lastTurnCompleted = true; waiters.formUnion(pending.values) }
        case let .exit(code, _): lastError = "exited \(code)"; waiters.formUnion(pending.values)
        default: break
        }
    }

    var currentThreadID: String?
    func enqueueDraft(cwd: String, text: String, model: String?, effort: String?, threadSandbox: String, turnSandbox: String, approvalPolicy: String) throws {}
    func updateSettings(model: String?, effort: String?, approvalPolicy: String?, sandboxPolicy: String?) throws -> Int { return 0 }
    func resolveApproval(requestID: Int, decision: String) throws {}
}

@MainActor
func runRelayCommandLiveProbe() throws {
    guard ProcessInfo.processInfo.environment["MACRELAY_RUN_LIVE_CODEX"] == "1" else {
        print("RelayCommandLiveProbe skipped (set MACRELAY_RUN_LIVE_CODEX=1 to run)")
        return
    }
    let cwd = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
    let detection = CodexCLIDetector.detect()
    guard detection.isInstalled, let codexPath = detection.executablePath else {
        throw ProbeError.failed("Codex CLI not installed: \(detection.errorMessage ?? "unknown")")
    }
    let bridge = LiveCodexRuntimeBridge(codexPath: codexPath, cwd: cwd)
    try bridge.start(cwd: cwd)
    try bridge.waitFor("turn/completed", timeout: 15)
    try expect(bridge.lastTurnCompleted, "turn not completed")
    bridge.stop()
    if let err = bridge.lastError { throw ProbeError.failed(err) }
    print("RelayCommandLiveProbe passed")
}
#endif

@main
struct RelayCommandLiveProbe {
    static func main() throws {
        #if os(macOS)
        try runRelayCommandLiveProbe()
        #else
        print("skipped: macOS only")
        #endif
    }
}
