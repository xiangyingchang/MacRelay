import Foundation

#if os(macOS)
import AgentClientCore

let cwd = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
let detection = CodexCLIDetector.detect()

guard detection.isInstalled, let codexPath = detection.executablePath else {
    print("Codex CLI not installed: \(detection.errorMessage ?? "unknown")")
    exit(1)
}

print("codex=\(codexPath)")
print("version=\(detection.version ?? "unknown")")

let client = CodexAppServerClient(codexCommand: codexPath, cwd: cwd)
let semaphore = DispatchSemaphore(value: 0)
let lock = NSLock()
var pending: [Int: String] = [:]
var failure: String?
var didFinish = false

func remember(_ id: Int, method: String) { lock.lock(); pending[id] = method; lock.unlock() }
func method(for id: Int) -> String? { lock.lock(); defer { lock.unlock() }; return pending.removeValue(forKey: id) }
func finish(_ error: String? = nil) { guard !didFinish else { return }; didFinish = true; failure = error; semaphore.signal() }

client.onEvent = { (event: CodexAppServerEvent) in
    switch event {
    case let .response(id, result, error):
        let m = method(for: id) ?? "unknown"
        if let error { finish("\(m) failed: \(error)"); return }
        print("response id=\(id) method=\(m) keys=\((result ?? [:]).keys.sorted())")
        if m == "initialize" {
            try? client.notification(method: "initialized")
            do {
                let sid = try client.request(method: "settings/update", params: ["settings": ["model": "test-model", "effort": "low"]])
                remember(sid, method: "settings/update")
            } catch { finish("settings/update failed: \(error)") }
        } else if m == "settings/update" { finish() }
    case let .notification(method, params): print("notification method=\(method) paramsKeys=\((params ?? [:]).keys.sorted())")
    case let .exit(code, _): finish("exited \(code)")
    case .stderr(let text): print("stderr \(text)")
    default: break
    }
}

do {
    try client.start()
    let id = try client.request(method: "initialize", params: ["clientInfo": ["name": "settings-update-live-probe", "title": "Settings Update Live Probe", "version": "0.1.0"]])
    remember(id, method: "initialize")
} catch { finish("start failed: \(error)") }

_ = semaphore.wait(timeout: .now() + 15)
client.stop()

if let failure { print("SettingsUpdateLiveProbe failed: \(failure)"); exit(1) }
print("SettingsUpdateLiveProbe passed")
#else
print("SettingsUpdateLiveProbe skipped: macOS only")
#endif
