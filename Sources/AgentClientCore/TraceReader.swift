import Foundation

// MARK: - Trace Warning

/// Warnings produced during trace reading. Non-fatal — reading continues.
public enum TraceWarning: Equatable {
    /// A duplicate `seq` number was detected. The first occurrence is kept.
    case duplicateSeq(UInt64, line: Int)
    /// A gap was detected in the `seq` sequence.
    case missingSeq(UInt64)
    /// A line could not be decoded. The event is skipped.
    case corruptLine(Int, String)
    /// An event had a future schema version and was skipped.
    case futureVersion(Int, line: Int)
}

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
/// - Diagnostic — reports duplicates, gaps, corrupt lines as warnings
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
    ///
    /// Corrupt lines are reported as warnings and skipped (no longer throws).
    /// Duplicate seq numbers are detected — the first occurrence wins.
    /// Gaps in the seq sequence are reported as warnings.
    public func readAll() -> TraceReadResult {
        guard let data = FileManager.default.contents(atPath: fileURL.path) else {
            return TraceReadResult(events: [], warnings: [])
        }
        guard let content = String(data: data, encoding: .utf8) else {
            return TraceReadResult(events: [], warnings: [
                .corruptLine(0, "File has invalid UTF-8 encoding")
            ])
        }

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var events: [RuntimeEvent] = []
        var warnings: [TraceWarning] = []
        var seenSeqs: Set<UInt64> = []

        for (index, line) in lines.enumerated() {
            guard let lineData = line.data(using: .utf8) else {
                warnings.append(.corruptLine(index, "Invalid UTF-8 on line \(index + 1)"))
                continue
            }
            do {
                let event = try decoder.decode(RuntimeEvent.self, from: lineData)
                // Skip events from a future schema version
                if event.version > RuntimeEvent.currentVersion {
                    warnings.append(.futureVersion(event.version, line: index))
                    continue
                }
                // Detect duplicate seq
                if let seq = event.seq {
                    if seenSeqs.contains(seq) {
                        warnings.append(.duplicateSeq(seq, line: index))
                        continue // Keep the first occurrence
                    }
                    seenSeqs.insert(seq)
                }
                events.append(event)
            } catch {
                warnings.append(.corruptLine(index, error.localizedDescription))
            }
        }

        // Sort by seq to guarantee ordering even if the file is appended out of order
        events.sort { ($0.seq ?? 0) < ($1.seq ?? 0) }

        // Detect gaps in the seq sequence
        let seqs = events.compactMap { $0.seq }.sorted()
        if let first = seqs.first, let last = seqs.last {
            let expectedSeqs = Set(first...last)
            let actualSeqs = Set(seqs)
            let missing = expectedSeqs.subtracting(actualSeqs).sorted()
            for seq in missing {
                warnings.append(.missingSeq(seq))
            }
        }

        return TraceReadResult(events: events, warnings: warnings)
    }

    /// Read events after a given sequence number.
    public func read(afterSeq: UInt64) -> [RuntimeEvent] {
        let result = readAll()
        return result.events.filter { ($0.seq ?? 0) > afterSeq }
    }
}

// MARK: - TraceReadResult

/// Result of reading a trace file, including metadata about the read.
public struct TraceReadResult {
    /// The decoded events, sorted by `seq`.
    public let events: [RuntimeEvent]

    /// Non-fatal warnings encountered during reading.
    public let warnings: [TraceWarning]

    /// Number of events skipped because their schema version was too new.
    public var skipped: Int {
        warnings.filter {
            if case .futureVersion = $0 { return true }
            return false
        }.count
    }

    /// Whether any events were skipped due to version incompatibility.
    public var hasSkippedEvents: Bool { skipped > 0 }

    /// Whether any warnings were produced.
    public var hasWarnings: Bool { !warnings.isEmpty }
}
