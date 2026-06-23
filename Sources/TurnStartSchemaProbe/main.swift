import Foundation

#if os(macOS)
import AgentClientCore

let cwd = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
let threadSandbox = CommandLine.arguments.dropFirst().dropFirst().first ?? "read-only"
let turnSandbox = CommandLine.arguments.dropFirst().dropFirst().dropFirst().first ?? "readOnly"
let detection = CodexCLIDetector.detect()

guard detection.isInstalled, let codexPath = detection.executablePath else {
    print("Codex CLI not installed: \(detection.errorMessage ?? "unknown")")
    exit(1)
}

print("codex=\(codexPath)")
print("version=\(detection.version ?? "unknown")")
print("thread/start sandbox=\(threadSandbox)")
print("turn/start sandboxPolicy.type=\(turnSandbox)")

let client = CodexAppServerClient(codexCommand: codexPath, cwd: cwd)
let semaphore = DispatchSemaphore(value: 0)
let lock = NSLock()
var pending: [Int: String] = [:]
var threadID: String?
var failure: String?
var didFinish = false

func remember(_ id: Int, method: String) { lock.lock(); pending[id] = method; lock.unlock() }
func method(for id: Int) -> String? { lock.lock(); defer { lock.unlock() }; return pending.removeValue(forKey: id) }
func finish(_ error: String? = nil) { guard !didFinish else { return }; didFinish = true; failure = error; semaphore.signal() }

func startTurnIfReady() {
    guard let threadID else { return }
    do {
        let id = try client.request(method: "turn/start", params: [
            "threadId": threadID, "input": [["type": "text", "text": "Reply ok."]],
            "approvalPolicy": "on-request", "sandboxPolicy": ["type": turnSandbox]
        ])
        remember(id, method: "turn/start")
    } catch { finish("turn/start request failed: \(error)") }
}

client.onEvent = { (event: CodexAppServerEvent) in
    switch event {
    case let .response(id, result, error):
        let m = method(for: id) ?? "unknown"
        if let error { print("response error id=\(id) method=\(m) error=\(error)"); finish("\(m) failed"); return }
        print("response id=\(id) method=\(m) keys=\((result ?? [:]).keys.sorted())")
        if m == "initialize" {
            try? client.notification(method: "initialized")
            do { let mid = try client.request(method: "model/list"); remember(mid, method: "model/list") }
            catch { finish("model/list request failed: \(error)") }
        } else if m == "model/list" {
            do {
                let id = try client.request(method: "thread/start", params: ["cwd": cwd, "sandbox": threadSandbox, "approvalPolicy": "on-request", "sessionStartSource": "startup"])
                remember(id, method: "thread/start")
            } catch { finish("thread/start request failed: \(error)") }
        } else if m == "thread/start" {
            if let id = result?["id"] as? String ?? (result?["thread"] as? [String: Any])?["id"] as? String { threadID = id; startTurnIfReady() }
        } else if m == "turn/start" { finish() }
    case let .notification(method, params):
        print("notification method=\(method) paramsKeys=\((params ?? [:]).keys.sorted())")
        if method == "thread/started", let id = params?["id"] as? String ?? (params?["thread"] as? [String: Any])?["id"] as? String { threadID = id; startTurnIfReady() }
    case let .serverRequest(id, method, _): print("serverRequest id=\(id) method=\(method)")
    case let .stderr(line): print("stderr \(line)")
    case let .exit(code, _): print("exit code=\(code)"); if !didFinish { finish("app-server exited before turn/start result") }
    default: break
    }
}

do {
    try client.start()
    let initializeID = try client.request(method: "initialize", params: ["clientInfo": ["name": "turn-start-schema-probe", "title": "Turn Start Schema Probe", "version": "0.1.0"]])
    remember(initializeID, method: "initialize")
} catch { finish("start failed: \(error)") }

_ = semaphore.wait(timeout: .now() + 15)
client.stop()

if let f = failure, !f.isEmpty { print("PROBE FAILED: \(f)"); exit(1) }
print("TurnStartSchemaProbe passed")
#else
print("TurnStartSchemaProbe skipped: macOS only")
#endif
