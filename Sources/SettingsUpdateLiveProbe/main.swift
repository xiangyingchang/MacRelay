import AgentClientCore
import Foundation

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
var threadID: String?
var failure: String?
var didFinish = false
var didRequestSettings = false

func remember(_ id: Int, method: String) {
    lock.lock()
    pending[id] = method
    lock.unlock()
}

func method(for id: Int) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return pending.removeValue(forKey: id)
}

func finish(_ error: String? = nil) {
    guard !didFinish else { return }
    didFinish = true
    failure = error
    semaphore.signal()
}

func requestSettingsUpdate() {
    guard !didRequestSettings else { return }
    guard let threadID else { return }
    didRequestSettings = true
    do {
        let id = try client.request(method: "thread/settings/update", params: [
            "threadId": threadID,
            "model": "gpt-5.4-mini",
            "effort": "low",
            "approvalPolicy": "on-request",
            "sandboxPolicy": ["type": "readOnly"]
        ])
        remember(id, method: "thread/settings/update")
    } catch {
        finish("thread/settings/update request failed: \(error)")
    }
}

client.onEvent = { event in
    switch event {
    case let .response(id, result, error):
        let method = method(for: id) ?? "unknown"
        if let error {
            print("response error id=\(id) method=\(method) error=\(error)")
            finish("\(method) failed")
            return
        }
        print("response id=\(id) method=\(method) keys=\((result ?? [:]).keys.sorted())")
        if method == "initialize" {
            try? client.notification(method: "initialized")
            do {
                let modelID = try client.request(method: "model/list")
                remember(modelID, method: "model/list")
            } catch {
                finish("model/list request failed: \(error)")
            }
        } else if method == "model/list" {
            do {
                let threadID = try client.request(method: "thread/start", params: [
                    "cwd": cwd,
                    "sandbox": "read-only",
                    "approvalPolicy": "on-request",
                    "sessionStartSource": "startup"
                ])
                remember(threadID, method: "thread/start")
            } catch {
                finish("thread/start request failed: \(error)")
            }
        } else if method == "thread/start" {
            if let id = result?["id"] as? String ?? (result?["thread"] as? [String: Any])?["id"] as? String {
                threadID = id
            }
            requestSettingsUpdate()
        } else if method == "thread/settings/update" {
            finish()
        }

    case let .notification(method, params):
        print("notification method=\(method) paramsKeys=\((params ?? [:]).keys.sorted())")
        if method == "thread/started" {
            if let id = params?["id"] as? String ?? (params?["thread"] as? [String: Any])?["id"] as? String {
                threadID = id
            }
            requestSettingsUpdate()
        }

    case let .serverRequest(id, method, _):
        print("serverRequest id=\(id) method=\(method)")

    case let .stderr(line):
        print("stderr \(line)")

    case let .raw(line):
        print("raw \(line)")

    case let .exit(code, _):
        print("exit code=\(code)")
        if !didFinish {
            finish("app-server exited before settings/update result")
        }
    }
}

do {
    try client.start()
    let initializeID = try client.request(method: "initialize", params: [
        "clientInfo": [
            "name": "agent-client-settings-update-live-probe",
            "title": "Agent Client Settings Update Live Probe",
            "version": "0.1.0"
        ],
        "capabilities": [
            "experimentalApi": true
        ]
    ])
    remember(initializeID, method: "initialize")
} catch {
    print("start failed: \(error)")
    client.stop()
    exit(1)
}

if semaphore.wait(timeout: .now() + .seconds(30)) == .timedOut {
    failure = "timed out waiting for settings/update"
}

client.stop()

if let failure {
    print("SettingsUpdateLiveProbe failed: \(failure)")
    exit(1)
}

print("SettingsUpdateLiveProbe passed")
