import Foundation

#if os(macOS)
import AgentClientCore

let cwd = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
let prompt = CommandLine.arguments.dropFirst().dropFirst().first ?? "Reply with exactly: ok"
let detection = CodexCLIDetector.detect()

guard detection.isInstalled, let codexPath = detection.executablePath else {
    print("Codex CLI not installed: \(detection.errorMessage ?? "unknown")")
    exit(1)
}

print("codex=\(codexPath)")
print("version=\(detection.version ?? "unknown")")
print("prompt=\(prompt)")

let client = CodexAppServerClient(codexCommand: codexPath, cwd: cwd)
let semaphore = DispatchSemaphore(value: 0)
let lock = NSLock()
var pending: [Int: String] = [:]
var failure: String?
var didFinish = false
let reducer = SessionStateReducer()
var snapshot = SessionSnapshot()

func remember(_ id: Int, method: String) { lock.lock(); pending[id] = method; lock.unlock() }
func method(for id: Int) -> String? { lock.lock(); defer { lock.unlock() }; return pending.removeValue(forKey: id) }
func finish(_ error: String? = nil) { guard !didFinish else { return }; didFinish = true; failure = error; semaphore.signal() }

client.onEvent = { (event: CodexAppServerEvent) in
    switch event {
    case let .response(id, result, error):
        let m = method(for: id) ?? "unknown"
        if let error { print("response error id=\(id) method=\(m) error=\(error)"); finish("\(m) failed"); return }
        print("response id=\(id) method=\(m) keys=\((result ?? [:]).keys.sorted())")
        if m == "initialize" {
            try? client.notification(method: "initialized")
            do { let tid = try client.request(method: "thread/start", params: ["cwd": cwd, "sandbox": "read-only", "approvalPolicy": "on-request", "sessionStartSource": "startup"]); remember(tid, method: "thread/start") }
            catch { finish("thread/start failed: \(error)") }
        } else if m == "thread/start" {
            do { let tid = try client.request(method: "turn/start", params: ["threadId": snapshot.threadID ?? "", "input": [["type": "text", "text": prompt]], "approvalPolicy": "on-request"]); remember(tid, method: "turn/start") }
            catch { finish("turn/start failed: \(error)") }
        } else if m == "turn/start" { finish() }
    case let .notification(method, params):
        print("notification method=\(method) paramsKeys=\((params ?? [:]).keys.sorted())")
        for action in reducer.actions(from: .notification(method: method, params: params)) { reducer.reduce(&snapshot, action: action) }
        if method == "thread/started", let id = params?["id"] as? String ?? (params?["thread"] as? [String: Any])?["id"] as? String { snapshot.threadID = id }
    case let .exit(code, _): finish("exited \(code)")
    case .stderr(let text): print("stderr \(text)")
    default: break
    }
}

do {
    try client.start()
    let id = try client.request(method: "initialize", params: ["clientInfo": ["name": "turn-event-trace-probe", "title": "Turn Event Trace Probe", "version": "0.1.0"]])
    remember(id, method: "initialize")
} catch { finish("start failed: \(error)") }

_ = semaphore.wait(timeout: .now() + 15)
client.stop()

if let failure { print("TurnEventTraceProbe failed: \(failure)"); exit(1) }
print("TurnEventTraceProbe passed finalText=\(snapshot.activeTurn?.assistantText ?? "")")
#else
print("TurnEventTraceProbe skipped: macOS only")
#endif
