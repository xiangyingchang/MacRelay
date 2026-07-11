import Foundation

// MARK: - TraceWriter

/// Persists RuntimeEvents to a JSONL file (one JSON object per line).
///
/// Directory structure:
///   .macrelay/sessions/{runID}/trace.jsonl
///
/// Design goals:
/// - Append only — never overwrite existing data
/// - seq strictly increasing (enforced by caller, verified here)
/// - Crash safe — `synchronizeFile()` after every write
/// - Thread-safe — uses NSLock for concurrent access
public final class TraceWriter: TraceStore {
    public let runID: String
    public let sessionID: String?
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var fileHandle: FileHandle?
    private var isSetup = false
    private var lastSeq: UInt64 = 0
    private var eventCount: Int = 0
    private let lock = NSLock()

    /// Create a TraceWriter for a specific run.
    ///
    /// - Parameters:
    ///   - runID: The unique run identifier.
    ///   - sessionID: Optional session identifier.
    ///   - baseDirectory: Base directory for trace storage. Defaults to `.macrelay/sessions/`.
    public init(
        runID: String,
        sessionID: String? = nil,
        baseDirectory: URL? = nil
    ) {
        self.runID = runID
        self.sessionID = sessionID

        let base = baseDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".macrelay/sessions")
        self.fileURL = base.appendingPathComponent("\(runID)/trace.jsonl")

        // Configure encoder
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        // Configure decoder
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    deinit {
        lock.lock()
        fileHandle?.closeFile()
        lock.unlock()
    }

    // MARK: - TraceStore

    public func append(_ event: RuntimeEvent) throws {
        lock.lock()
        defer { lock.unlock() }

        try ensureFileHandle()

        let data: Data
        do {
            data = try encoder.encode(event)
        } catch {
            throw TraceStoreError.encodingError(event, error)
        }

        // Append newline after each JSON object
        var lineData = data
        lineData.append(contentsOf: [0x0A]) // newline

        guard let handle = fileHandle else {
            throw TraceStoreError.fileNotFound(fileURL.path)
        }

        handle.write(lineData)
        handle.synchronizeFile()

        lastSeq = event.seq ?? lastSeq
        eventCount += 1
    }

    public func append(contentsOf events: [RuntimeEvent]) throws {
        for event in events {
            try append(event)
        }
    }

    public func readAll() throws -> [RuntimeEvent] {
        lock.lock()
        defer { lock.unlock() }

        // Ensure we're set up and have the correct event count
        try ensureFileHandle()

        guard let data = FileManager.default.contents(atPath: fileURL.path) else {
            return []
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw TraceStoreError.invalidEncoding(fileURL.path)
        }

        var events: [RuntimeEvent] = []
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for (index, line) in lines.enumerated() {
            guard let lineData = line.data(using: .utf8) else {
                throw TraceStoreError.invalidEncoding(fileURL.path)
            }
            do {
                let event = try decoder.decode(RuntimeEvent.self, from: lineData)
                events.append(event)
            } catch {
                throw TraceStoreError.decodingError(index, fileURL.path, error)
            }
        }

        return events
    }

    public func read(afterSeq: UInt64) throws -> [RuntimeEvent] {
        let all = try readAll()
        return all.filter { ($0.seq ?? 0) > afterSeq }
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return eventCount
    }

    // MARK: - Private

    /// Create parent directories and open file handle for appending.
    private func ensureFileHandle() throws {
        guard !isSetup else { return }

        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw TraceStoreError.directoryCreationFailed(dir.path, error)
        }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        handle.seekToEndOfFile()
        self.fileHandle = handle
        self.isSetup = true

        // Count existing events
        self.eventCount = try Self.countEvents(in: fileURL.path)
    }

    /// Count events in a trace file.
    static func countEvents(in path: String) throws -> Int {
        guard let data = FileManager.default.contents(atPath: path) else {
            return 0
        }
        guard let content = String(data: data, encoding: .utf8) else {
            return 0
        }
        return content.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
    }
}

// MARK: - In-Memory TraceStore (for testing)

/// In-memory implementation of TraceStore for testing.
public final class InMemoryTraceStore: TraceStore {
    public let runID: String
    public let sessionID: String?
    private var events: [RuntimeEvent] = []
    private let lock = NSLock()

    public init(runID: String, sessionID: String? = nil) {
        self.runID = runID
        self.sessionID = sessionID
    }

    public func append(_ event: RuntimeEvent) throws {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    public func append(contentsOf events: [RuntimeEvent]) throws {
        lock.lock()
        defer { lock.unlock() }
        self.events.append(contentsOf: events)
    }

    public func readAll() throws -> [RuntimeEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    public func read(afterSeq: UInt64) throws -> [RuntimeEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events.filter { ($0.seq ?? 0) > afterSeq }
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return events.count
    }
}
