import Foundation

public final class JSONRPCWriter {
    private var nextRequestID = 1
    private let input: FileHandle
    private let lock = NSLock()

    public init(input: FileHandle) {
        self.input = input
    }

    @discardableResult
    public func request(method: String, params: Any = [:]) throws -> Int {
        let id = lock.withLock {
            let id = nextRequestID
            nextRequestID += 1
            return id
        }

        try send([
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ])

        return id
    }

    public func notification(method: String, params: Any? = nil) throws {
        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]

        if let params {
            message["params"] = params
        }

        try send(message)
    }

    public func response(id: Int, result: Any) throws {
        try send([
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ])
    }

    private func send(_ message: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        lock.lock()
        defer { lock.unlock() }
        input.write(data)
        input.write(Data([0x0A]))
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
