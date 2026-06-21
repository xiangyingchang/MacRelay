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
var didReceiveModels = false
var failure: String?

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

client.onEvent = { event in
    switch event {
    case let .response(id, result, error):
        let method = method(for: id) ?? "unknown"
        if let error {
            print("response error id=\(id) method=\(method) error=\(error)")
            failure = "\(method) failed"
            semaphore.signal()
            return
        }

        print("response id=\(id) method=\(method) keys=\((result ?? [:]).keys.sorted())")
        if method == "initialize" {
            try? client.notification(method: "initialized")
            do {
                let modelID = try client.request(method: "model/list")
                remember(modelID, method: "model/list")
            } catch {
                failure = "model/list request failed: \(error)"
                semaphore.signal()
            }
        } else if method == "model/list" {
            let models = result?["data"] as? [[String: Any]] ?? result?["models"] as? [[String: Any]] ?? []
            let names = models.prefix(5).map { model in
                model["model"] as? String
                    ?? model["slug"] as? String
                    ?? model["name"] as? String
                    ?? model["displayName"] as? String
                    ?? "unknown"
            }
            print("models.prefix=\(names.joined(separator: ", "))")
            didReceiveModels = true
            semaphore.signal()
        }

    case let .notification(method, _):
        print("notification method=\(method)")

    case let .serverRequest(id, method, _):
        print("serverRequest id=\(id) method=\(method)")

    case let .stderr(line):
        print("stderr \(line)")

    case let .raw(line):
        print("raw \(line)")

    case let .exit(code, _):
        print("exit code=\(code)")
        if !didReceiveModels {
            failure = "app-server exited before model/list"
            semaphore.signal()
        }
    }
}

do {
    try client.start()
    let initializeID = try client.request(method: "initialize", params: [
        "clientInfo": [
            "name": "agent-client-init-probe",
            "title": "Agent Client Init Probe",
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

let timeout = DispatchTime.now() + .seconds(30)
if semaphore.wait(timeout: timeout) == .timedOut {
    failure = "timed out waiting for model/list"
}

client.stop()

if let failure {
    print("CodexAppServerInitProbe failed: \(failure)")
    exit(1)
}

print("CodexAppServerInitProbe passed")
