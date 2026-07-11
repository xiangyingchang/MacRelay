import Foundation

// MARK: - ReplayService

/// Rebuilds `SessionSnapshot` from persisted trace files.
///
/// Usage:
///
///     let service = ReplayService(baseDirectory: traceBaseDir)
///     let snapshot = try service.rebuild(runID: "run-001")
///
/// The service reads `trace.jsonl`, feeds every event through the reducer,
/// and returns the resulting snapshot. No live runtime connection required —
/// the trace file is the sole source of truth.
public struct ReplayService {
    private let baseDirectory: URL

    /// Create a replay service that reads traces from the given base directory.
    ///
    /// The default path is `.macrelay/sessions/` relative to the current directory,
    /// matching TraceWriter's default output.
    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".macrelay/sessions")
    }

    // MARK: - Public API

    /// Rebuild a snapshot from a run's trace file.
    ///
    /// - Parameter runID: The run identifier whose trace to replay.
    /// - Returns: The rebuilt `SessionSnapshot`.
    /// - Throws: `ReplayError.traceNotFound` if no trace file exists for the run.
    ///           `TraceStoreError` if the file cannot be decoded.
    public func rebuild(runID: String) throws -> SessionSnapshot {
        let reader = TraceReader(runID: runID, baseDirectory: baseDirectory)
        guard reader.exists else {
            throw ReplayError.traceNotFound(runID: runID)
        }
        let result = reader.readAll()
        guard !result.events.isEmpty else {
            return SessionSnapshot()
        }
        return SnapshotRebuilder.rebuild(from: result.events)
    }

    /// Rebuild a snapshot and timeline from a run's trace file.
    ///
    /// Returns both the state snapshot and the UI timeline in a single pass,
    /// avoiding duplicate file reads.
    public func rebuildWithTimeline(runID: String) throws -> (snapshot: SessionSnapshot, timeline: [TimelineItem]) {
        let reader = TraceReader(runID: runID, baseDirectory: baseDirectory)
        guard reader.exists else {
            throw ReplayError.traceNotFound(runID: runID)
        }
        let result = reader.readAll()
        guard !result.events.isEmpty else {
            return (SessionSnapshot(), [])
        }
        return SnapshotRebuilder.rebuildWithTimeline(from: result.events)
    }

    /// List all runIDs that have trace files in the base directory.
    public func availableRuns() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return contents
            .filter { url in
                let traceURL = url.appendingPathComponent("trace.jsonl")
                return FileManager.default.fileExists(atPath: traceURL.path)
            }
            .map { $0.lastPathComponent }
            .sorted()
    }
}

// MARK: - ReplayError

public enum ReplayError: Error, LocalizedError {
    case traceNotFound(runID: String)

    public var errorDescription: String? {
        switch self {
        case .traceNotFound(let runID):
            return "No trace file found for runID: \(runID)"
        }
    }
}
