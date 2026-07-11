import Foundation

// MARK: - RunDetail

/// Complete view of a single run, combining metadata, timeline, and file changes.
public struct RunDetail {
    /// The run's persistent metadata.
    public let metadata: RunMetadata

    /// Timeline events for this run (ordered by time).
    public let timeline: [TimelineItem]

    /// Files changed during this run.
    public let changedFiles: [String]

    /// The run's final snapshot (for status, result, etc.).
    public let snapshot: SessionSnapshot

    public init(
        metadata: RunMetadata,
        timeline: [TimelineItem],
        changedFiles: [String],
        snapshot: SessionSnapshot
    ) {
        self.metadata = metadata
        self.timeline = timeline
        self.changedFiles = changedFiles
        self.snapshot = snapshot
    }

    /// Duration of the run, if completed.
    public var duration: TimeInterval? {
        metadata.run.duration
    }

    /// Summary text from the run's result.
    public var resultSummary: String? {
        metadata.run.resultSummary
    }
}

// MARK: - RunHistoryStore Protocol

/// Query interface for run history.
///
/// Abstracts away the combination of RunMetadataStore + ReplayService,
/// providing a single entry point for UI code.
public protocol RunHistoryStore: Sendable {
    /// List all runs for a given session, ordered by creation time.
    func listRuns(sessionID: String) throws -> [RunMetadata]

    /// List all runs across all sessions.
    func listAllRuns() throws -> [RunMetadata]

    /// Load full details for a single run.
    func loadRunDetail(runID: String) throws -> RunDetail

    /// Check if a run exists.
    func runExists(runID: String) -> Bool
}

// MARK: - FileRunHistoryStore

/// Combines RunMetadataStore + ReplayService to provide run history queries.
///
/// Directory structure:
///   .macrelay/sessions/{runID}/metadata.json
///   .macrelay/sessions/{runID}/trace.jsonl
public final class FileRunHistoryStore: RunHistoryStore {
    private let metadataStore: RunMetadataStore
    private let replayService: ReplayService

    public init(
        metadataStore: RunMetadataStore? = nil,
        replayService: ReplayService? = nil,
        baseDirectory: URL? = nil
    ) {
        let base = baseDirectory
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".macrelay/sessions")

        self.metadataStore = metadataStore ?? FileRunMetadataStore(baseDirectory: base)
        self.replayService = replayService ?? ReplayService(baseDirectory: base)
    }

    // MARK: - RunHistoryStore

    public func listRuns(sessionID: String) throws -> [RunMetadata] {
        try metadataStore.listRuns(sessionID: sessionID)
    }

    public func listAllRuns() throws -> [RunMetadata] {
        // Scan all run directories for metadata
        let baseDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".macrelay/sessions")

        guard FileManager.default.fileExists(atPath: baseDirectory.path) else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var results: [RunMetadata] = []
        for dir in contents {
            let runID = dir.lastPathComponent
            if let metadata = try? metadataStore.load(runID: runID) {
                results.append(metadata)
            }
        }

        return results.sorted { ($0.run.startedAt ?? $0.run.createdAt) < ($1.run.startedAt ?? $1.run.createdAt) }
    }

    public func loadRunDetail(runID: String) throws -> RunDetail {
        // 1. Load metadata
        guard let metadata = try metadataStore.load(runID: runID) else {
            throw RunHistoryStoreError.metadataNotFound(runID)
        }

        // 2. Rebuild snapshot + timeline from trace
        let (snapshot, timeline) = try replayService.rebuildWithTimeline(runID: runID)

        // 3. Extract changed files from snapshot
        let changedFiles = Array(snapshot.fileChanges.keys)

        return RunDetail(
            metadata: metadata,
            timeline: timeline,
            changedFiles: changedFiles,
            snapshot: snapshot
        )
    }

    public func runExists(runID: String) -> Bool {
        metadataStore.exists(runID: runID)
    }
}

// MARK: - RunHistoryStore Error

public enum RunHistoryStoreError: Error, LocalizedError {
    case metadataNotFound(String)
    case traceNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .metadataNotFound(let runID):
            return "Run metadata not found: \(runID)"
        case .traceNotFound(let runID):
            return "Run trace not found: \(runID)"
        }
    }
}

// MARK: - In-Memory RunHistoryStore (for testing)

/// In-memory implementation of RunHistoryStore for testing.
public final class InMemoryRunHistoryStore: RunHistoryStore {
    private var runs: [String: RunDetail] = [:]

    public init() {}

    public func addRun(_ detail: RunDetail) {
        runs[detail.metadata.run.id] = detail
    }

    public func listRuns(sessionID: String) throws -> [RunMetadata] {
        runs.values
            .filter { $0.metadata.sessionID == sessionID }
            .map { $0.metadata }
            .sorted { ($0.run.startedAt ?? $0.run.createdAt) < ($1.run.startedAt ?? $1.run.createdAt) }
    }

    public func listAllRuns() throws -> [RunMetadata] {
        runs.values
            .map { $0.metadata }
            .sorted { ($0.run.startedAt ?? $0.run.createdAt) < ($1.run.startedAt ?? $1.run.createdAt) }
    }

    public func loadRunDetail(runID: String) throws -> RunDetail {
        guard let detail = runs[runID] else {
            throw RunHistoryStoreError.metadataNotFound(runID)
        }
        return detail
    }

    public func runExists(runID: String) -> Bool {
        runs[runID] != nil
    }
}
