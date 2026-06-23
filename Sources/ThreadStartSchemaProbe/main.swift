import AgentClientCore
import Foundation

@main
struct ThreadStartSchemaProbe {
    static func main() {
        #if os(macOS)
        let cwd = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
        let sandbox = CommandLine.arguments.dropFirst().dropFirst().first ?? "readOnly"
        let detection = CodexCLIDetector.detect()

        guard detection.isInstalled, let codexPath = detection.executablePath else {
            print("Codex CLI not installed: \(detection.errorMessage ?? "unknown")")
            exit(1)
        }

        print("codex=\(codexPath)")
        print("version=\(detection.version ?? "unknown")")
        print("thread/start sandbox=\(sandbox)")

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
                if let error { print("response error id=\(id) method=\(m) error=\(error)"); finish("\(m) failed"); return }
                print("response id=\(id) method=\(m) keys=\((result ?? [:]).keys.sorted())")
                if m == "initialize" {
                    try? client.notification(method: "initialized")
                    do { let mid = try client.request(method: "model/list"); remember(mid, method: "model/list") }
                    catch { finish("model/list request failed: \(error)") }
                } else if m == "model/list" {
                    do {
                        let tid = try client.request(method: "thread/start", params: ["cwd": cwd, "sandbox": sandbox, "approvalPolicy": "on-request", "sessionStartSource": "startup"])
                        remember(tid, method: "thread/start")
                    } catch { finish("thread/start request failed: \(error)") }
                } else if m == "thread/start" { finish() }
            case let .notification(method, params):
                print("notification method=\(method) paramsKeys=\((params ?? [:]).keys.sorted())")
                if method == "thread/started" { finish() }
            case .exit: finish("codex exited")
            case .stderr(let text): print("stderr: \(text)")
            default: break
            }
        }

        do {
            try client.start()
            let id = try client.request(method: "initialize", params: ["clientInfo": ["name": "thread-start-schema-probe", "title": "Thread Start Schema Probe", "version": "0.1.0"]])
            remember(id, method: "initialize")
        } catch { finish("start failed: \(error)") }

        _ = semaphore.wait(timeout: .now() + 15)
        client.stop()

        if let f = failure, !f.isEmpty { print("PROBE FAILED: \(f)"); exit(1) }
        print("ThreadStartSchemaProbe passed")
        #else
        print("skipped: macOS only")
        #endif
    }
}
