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
var failure: String?

client.onEvent = { (event: CodexAppServerEvent) in
    switch event {
    case let .response(id, result, error):
        if let error { print("response error id=\(id) error=\(error)"); failure = "initialize failed: \(error)" }
        else { print("response id=\(id) keys=\((result ?? [:]).keys.sorted())") }
        semaphore.signal()
    case let .notification(method, params):
        print("notification method=\(method) paramsKeys=\((params ?? [:]).keys.sorted())")
    case let .serverRequest(id, method, _): print("serverRequest id=\(id) method=\(method)")
    case let .stderr(line): print("stderr \(line)")
    case let .exit(code, _): print("exit code=\(code)"); if failure == nil { failure = "app-server exited before response" }; semaphore.signal()
    default: break
    }
}

do {
    try client.start()
    _ = try client.request(method: "initialize", params: [
        "clientInfo": ["name": "codex-init-probe", "title": "Codex Init Probe", "version": "0.1.0"]
    ])
} catch { failure = "start failed: \(error)"; semaphore.signal() }

_ = semaphore.wait(timeout: .now() + 10)
client.stop()

if let f = failure { print("PROBE FAILED: \(f)"); exit(1) }
print("CodexAppServerInitProbe passed")
#else
print("CodexAppServerInitProbe skipped: macOS only")
#endif
