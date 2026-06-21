import Foundation

public enum CodexAppServerEvent {
    case response(id: Int, result: [String: Any]?, error: Any?)
    case serverRequest(id: Int, method: String, params: [String: Any]?)
    case notification(method: String, params: [String: Any]?)
    case stderr(String)
    case raw(String)
    case exit(code: Int32, reason: Process.TerminationReason)
}

public final class CodexAppServerClient {
    public var onEvent: ((CodexAppServerEvent) -> Void)?

    private let codexCommand: String
    private let cwd: String
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdoutBuffer = LineDelimitedJSONBuffer()
    private let stderrBuffer = LineDelimitedJSONBuffer()
    private var writer: JSONRPCWriter?

    public init(codexCommand: String = "codex", cwd: String) {
        self.codexCommand = codexCommand
        self.cwd = cwd
    }

    public func start() throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [codexCommand, "app-server", "--stdio"]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = CodexCLIDetector.codexProcessEnvironment()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        writer = JSONRPCWriter(input: stdinPipe.fileHandleForWriting)

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }

            for line in self.stdoutBuffer.append(data) {
                self.handleStdoutLine(line)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }

            for line in self.stderrBuffer.append(data) {
                self.onEvent?(.stderr(line))
            }
        }

        process.terminationHandler = { [weak self] process in
            self?.stdoutPipe.fileHandleForReading.readabilityHandler = nil
            self?.stderrPipe.fileHandleForReading.readabilityHandler = nil
            self?.onEvent?(.exit(code: process.terminationStatus, reason: process.terminationReason))
        }

        try process.run()
    }

    public func stop() {
        if process.isRunning {
            process.terminate()
        }
    }

    @discardableResult
    public func request(method: String, params: Any = [:]) throws -> Int {
        guard let writer else {
            throw CodexAppServerClientError.notStarted
        }
        return try writer.request(method: method, params: params)
    }

    public func notification(method: String, params: Any? = nil) throws {
        guard let writer else {
            throw CodexAppServerClientError.notStarted
        }
        try writer.notification(method: method, params: params)
    }

    public func response(id: Int, result: Any) throws {
        guard let writer else {
            throw CodexAppServerClientError.notStarted
        }
        try writer.response(id: id, result: result)
    }

    private func handleStdoutLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            onEvent?(.raw(line))
            return
        }

        if let id = message["id"] as? Int, let method = message["method"] as? String {
            onEvent?(.serverRequest(
                id: id,
                method: method,
                params: message["params"] as? [String: Any]
            ))
            return
        }

        if let id = message["id"] as? Int {
            onEvent?(.response(
                id: id,
                result: message["result"] as? [String: Any],
                error: message["error"]
            ))
            return
        }

        if let method = message["method"] as? String {
            onEvent?(.notification(
                method: method,
                params: message["params"] as? [String: Any]
            ))
            return
        }

        onEvent?(.raw(line))
    }
}

public enum CodexAppServerClientError: Error {
    case notStarted
}
