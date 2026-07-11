import Foundation

// MARK: - TraceReader

/// Reads a `trace.jsonl` file and decodes each line into a `RuntimeEvent`.
///
/// This is the read-only counterpart to `TraceWriter`. Use it to replay
/// a persisted trace and rebuild state without a live runtime connection.
///
/// Design goals:
/// - Stateless — no side effects, no locks
/// - Version-aware — skips events with unsupported schema versions
/// - Ordered — returns events sorted by `seq`
public struct TraceReader {
    private let fileURL: URL
    private let decoder: JSONDecoder

    /// Create a reader for a specific trace file.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// Create a reader for a run's trace file inside a base directory.
    ///
    /// Resolves to `{baseDirectory}/{runID}/trace.jsonl`.
    public init(runID: String, baseDirectory: URL) {
        self.fileURL = baseDirectory
            .appendingPathComponent(runID)
            .appendingPathComponent("trace.jsonl")
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public API

    /// Whether the trace file exists on disk.
    public var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Read all events from the trace file, sorted by `seq`.
    ///
    /// Events with a `version` higher than `RuntimeEvent.currentVersion` are
    /// skipped with a warning — they carry payloads the current reducer cannot
    /// interpret. This is the forward-compatibility guarantee: old traces always
    /// load; new events on old readers degrade gracefully.
    public func readAll() throws -> TraceReadResult {
        guard let data = FileManager.default.contents(atPath: fileURL.path) else {
            return TraceReadResult(events: [], skipped: 0)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw TraceStoreError.invalidEncoding(fileURL.path)
        }

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var events: [RuntimeEvent] = []
        var skipped = 0

        for (index, line) in lines.enumerated() {
            guard let lineData = line.data(using: .utf8) else {
                throw TraceStoreError.invalidEncoding(fileURL.path)
            }
            do {
                let event = try decoder.decode(RuntimeEvent.self, from: lineData)
                // Skip events from a future schema version
                if event.version > RuntimeEvent.currentVersion {
                    skipped += 1
                    continue
                }
                events.append(event)
            } catch {
                throw TraceStoreError.decodingError(index, fileURL.path, error)
            }
        }

        // Sort by seq to guarantee ordering even if the file is appended out of order
        events.sort { ($0.seq ?? 0) < ($1.seq ?? 0) }

        return TraceReadResult(events: events, skipped: skipped)
    }

    /// Read events after a given sequence number.
    public func read(afterSeq: UInt64) throws -> [RuntimeEvent] {
        let result = try readAll()
        return result.events.filter { ($0.seq ?? 0) > afterSeq }
    }
}

// MARK: - TraceReadResult

/// Result of reading a trace file, including metadata about the read.
public struct TraceReadResult {
    /// The decoded events, sorted by `seq`.
    public let events: [RuntimeEvent]

    /// Number of events skipped because their schema version was too new.
    public let skipped: Int

    /// Whether any events were skipped due to version incompatibility.
    public var hasSkippedEvents: Bool { skipped > 0 }
}
