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
final class LiveApprovalBridge {
    let client: CodexAppServerClient
    private var pending: [Int: String] = [:]
    private var waiters: Set<String> = []
    var lastTurnCompleted = false
    var lastError: String?
    var approvalRequested = false

    init(codexPath: String, cwd: String) {
        self.client = CodexAppServerClient(codexCommand: codexPath, cwd: cwd)
        self.client.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    func start(cwd: String) throws {
        try client.start()
        let id = try client.request(method: "initialize", params: [
            "clientInfo": ["name": "approval-probe", "title": "Approval Probe", "version": "0.1.0"]])
        pending[id] = "initialize"
    }

    func stop() { client.stop() }

    func waitFor(_ method: String, timeout seconds: Int) throws {
        if method == "turn/completed", lastTurnCompleted { return }
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            if method == "turn/completed", lastTurnCompleted { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func handle(_ event: CodexAppServerEvent) {
        switch event {
        case let .response(id, result, error):
            guard let method = pending.removeValue(forKey: id) else { return }
            if method == "initialize" {
                try? client.notification(method: "initialized")
                do {
                    let tid = try client.request(method: "thread/start", params: [
                        "cwd": "/tmp/ap-\(UUID().uuidString.prefix(4))",
                        "sandbox": "readOnly", "approvalPolicy": "on-request", "sessionStartSource": "startup"])
                    pending[tid] = "thread/start"
                } catch { lastError = "\(error)" }
            } else if method == "thread/start" {
                do {
                    let tid = try client.request(method: "turn/start", params: [
                        "threadId": result?["id"] as? String ?? "",
                        "input": [["type": "text", "text": "Create hello.txt with content ok"]],
                        "approvalPolicy": "on-request", "sandboxPolicy": ["type": "readOnly"]])
                    pending[tid] = "turn/start"
                } catch { lastError = "\(error)" }
            }
        case let .serverRequest(id, method, _):
            if method.contains("requestApproval") {
                approvalRequested = true
                waiters.formUnion(pending.values)
                try? client.response(id: id, result: ["decision": "accept"])
            }
        case let .notification(method, params):
            if method == "turn/completed" { lastTurnCompleted = true; waiters.formUnion(pending.values) }
        case let .exit(code, _): lastError = "exited \(code)"; waiters.formUnion(pending.values)
        default: break
        }
    }
}

@MainActor
func runApprovalProbe() throws {
    guard ProcessInfo.processInfo.environment["MACRELAY_RUN_LIVE_APPROVAL"] == "1" else {
        print("RelayApprovalLiveProbe skipped (set MACRELAY_RUN_LIVE_APPROVAL=1 to run)")
        print("WARNING: this probe burns Codex quota and creates files. Use sparingly.")
        return
    }
    let cwd = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
    let detection = CodexCLIDetector.detect()
    guard detection.isInstalled, let codexPath = detection.executablePath else {
        throw ProbeError.failed("Codex CLI not installed: \(detection.errorMessage ?? "unknown")")
    }
    let bridge = LiveApprovalBridge(codexPath: codexPath, cwd: cwd)
    try bridge.start(cwd: cwd)
    try bridge.waitFor("approval/requested", timeout: 20)
    try expect(bridge.approvalRequested, "approval not requested")
    try bridge.waitFor("turn/completed", timeout: 15)
    try expect(bridge.lastTurnCompleted, "turn not completed")
    bridge.stop()
    if let err = bridge.lastError { throw ProbeError.failed(err) }
    print("RelayApprovalLiveProbe passed approval+turn")
}
#endif

@main
struct RelayApprovalLiveProbe {
    static func main() throws {
        #if os(macOS)
        try runApprovalProbe()
        #else
        print("skipped: macOS only")
        #endif
    }
}
