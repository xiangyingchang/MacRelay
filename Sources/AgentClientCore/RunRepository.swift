import Foundation

// MARK: - RunRepository Protocol

/// Persistence layer for AgentRun objects.
///
/// Organizes runs under sessions with an index file for fast listing:
/// ```
/// .macrelay/sessions/{sessionID}/runs/{runID}/metadata.json
/// .macrelay/sessions/{sessionID}/runs/index.json
/// ```
///
/// Business code should depend on this protocol instead of directly
/// operating on files. This enables testing with in-memory implementations.
public protocol RunRepository: Sendable {
    /// Persist a new run. Throws if the run already exists.
    func createRun(_ run: AgentRun, in sessionID: String) throws

    /// Update an existing run's metadata. Throws if the run does not exist.
    func updateRun(_ run: AgentRun) throws

    /// Retrieve a single run by ID. Returns nil if not found.
    func getRun(runID: String) throws -> AgentRun?

    /// List all runs for a given session, sorted by createdAt ascending.
    func listRuns(sessionID: String) throws -> [AgentRun]

    /// List all runs across all sessions for a given workspace path, sorted by createdAt ascending.
    func listRuns(workspace: String) throws -> [AgentRun]
}

// MARK: - RunRepository Error

public enum RunRepositoryError: Error, LocalizedError {
    case alreadyExists(String)
    case notFound(String)
    case encodingError(AgentRun, Error)
    case decodingError(String, Error)
    case directoryCreationFailed(String, Error)
    case fileWriteFailed(String, Error)
    case indexCorrupted(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyExists(let runID):
            return "Run already exists: \(runID)"
        case .notFound(let runID):
            return "Run not found: \(runID)"
        case .encodingError(_, let error):
            return "Failed to encode run: \(error.localizedDescription)"
        case .decodingError(let path, let error):
            return "Failed to decode run at \(path): \(error.localizedDescription)"
        case .directoryCreationFailed(let path, let error):
            return "Failed to create directory \(path): \(error.localizedDescription)"
        case .fileWriteFailed(let path, let error):
            return "Failed to write \(path): \(error.localizedDescription)"
        case .indexCorrupted(let path):
            return "Run index corrupted at \(path)"
        }
    }
}

// MARK: - Index Entry (lightweight record for the index file)

/// A lightweight entry in the session run index, enabling fast listing
/// without reading every metadata.json.
internal struct RunIndexEntry: Codable, Equatable {
    let runID: String
    let sessionID: String
    let status: RunStatus
    let createdAt: Date
    let startedAt: Date?
    let finishedAt: Date?
    let provider: String?
    let model: String?

    init(from run: AgentRun) {
        self.runID = run.id
        self.sessionID = run.sessionID
        self.status = run.status
        self.createdAt = run.createdAt
        self.startedAt = run.startedAt
        self.finishedAt = run.finishedAt
        self.provider = run.provider
        self.model = run.model
    }
}

// MARK: - FileRunRepository

/// File-system implementation of RunRepository.
///
/// Directory layout:
/// ```
/// .macrelay/sessions/{sessionID}/runs/{runID}/metadata.json
/// .macrelay/sessions/{sessionID}/runs/index.json
/// ```
///
/// Design goals:
/// - Crash safe — atomic writes via temp file + rename
/// - Thread-safe — uses NSLock for concurrent access
/// - Index maintained for fast listing without scanning all metadata files
public final class FileRunRepository: RunRepository {
    private let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    /// - Parameter baseDirectory: Base directory for session storage.
    ///   Defaults to `.macrelay/sessions/` under the current working directory.
    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".macrelay/sessions")

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - RunRepository

    public func createRun(_ run: AgentRun, in sessionID: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let runDir = runsDirectory(sessionID: sessionID).appendingPathComponent(run.id)
        let metadataURL = runDir.appendingPathComponent("metadata.json")

        // Guard: must not already exist
        guard !FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw RunRepositoryError.alreadyExists(run.id)
        }

        // Write metadata
        try ensureDirectory(runDir)
        let metadata = RunMetadata(run: run, sessionID: sessionID, tracePath: run.tracePath)
        try writeMetadata(metadata, to: metadataURL)

        // Update index
        try appendToIndex(sessionID: sessionID, entry: RunIndexEntry(from: run))
    }

    public func updateRun(_ run: AgentRun) throws {
        lock.lock()
        defer { lock.unlock() }

        let runDir = runsDirectory(sessionID: run.sessionID).appendingPathComponent(run.id)
        let metadataURL = runDir.appendingPathComponent("metadata.json")

        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw RunRepositoryError.notFound(run.id)
        }

        let metadata = RunMetadata(run: run, sessionID: run.sessionID, tracePath: run.tracePath)
        try writeMetadata(metadata, to: metadataURL)

        // Update index entry
        try updateIndexEntry(sessionID: run.sessionID, entry: RunIndexEntry(from: run))
    }

    public func getRun(runID: String) throws -> AgentRun? {
        lock.lock()
        defer { lock.unlock() }

        // We need to find which session this run belongs to.
        // Scan session directories for the run.
        guard FileManager.default.fileExists(atPath: baseDirectory.path) else {
            return nil
        }

        let sessions = try FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for sessionDir in sessions {
            let metadataURL = sessionDir
                .appendingPathComponent("runs")
                .appendingPathComponent(runID)
                .appendingPathComponent("metadata.json")

            guard FileManager.default.fileExists(atPath: metadataURL.path) else { continue }

            do {
                let data = try Data(contentsOf: metadataURL)
                let metadata = try decoder.decode(RunMetadata.self, from: data)
                return metadata.run
            } catch {
                throw RunRepositoryError.decodingError(metadataURL.path, error)
            }
        }

        return nil
    }

    public func listRuns(sessionID: String) throws -> [AgentRun] {
        lock.lock()
        defer { lock.unlock() }

        let indexURL = runsDirectory(sessionID: sessionID).appendingPathComponent("index.json")

        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: indexURL)
            let entries = try decoder.decode([RunIndexEntry].self, from: data)
            return try entries
                .sorted { $0.createdAt < $1.createdAt }
                .map { entry in
                    let metadataURL = runsDirectory(sessionID: sessionID)
                        .appendingPathComponent(entry.runID)
                        .appendingPathComponent("metadata.json")
                    let mData = try Data(contentsOf: metadataURL)
                    let metadata = try decoder.decode(RunMetadata.self, from: mData)
                    return metadata.run
                }
        } catch let error as RunRepositoryError {
            throw error
        } catch {
            throw RunRepositoryError.indexCorrupted(indexURL.path)
        }
    }

    public func listRuns(workspace: String) throws -> [AgentRun] {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: baseDirectory.path) else {
            return []
        }

        let sessions = try FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var allRuns: [AgentRun] = []

        for sessionDir in sessions {
            let indexURL = sessionDir
                .appendingPathComponent("runs")
                .appendingPathComponent("index.json")

            guard FileManager.default.fileExists(atPath: indexURL.path) else { continue }

            do {
                let data = try Data(contentsOf: indexURL)
                let entries = try decoder.decode([RunIndexEntry].self, from: data)
                for entry in entries {
                    let metadataURL = sessionDir
                        .appendingPathComponent("runs")
                        .appendingPathComponent(entry.runID)
                        .appendingPathComponent("metadata.json")
                    guard FileManager.default.fileExists(atPath: metadataURL.path) else { continue }
                    let mData = try Data(contentsOf: metadataURL)
                    let metadata = try decoder.decode(RunMetadata.self, from: mData)
                    allRuns.append(metadata.run)
                }
            } catch {
                // Skip corrupted sessions
                continue
            }
        }

        return allRuns.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Private Helpers

    private func runsDirectory(sessionID: String) -> URL {
        baseDirectory.appendingPathComponent(sessionID).appendingPathComponent("runs")
    }

    private func writeMetadata(_ metadata: RunMetadata, to url: URL) throws {
        let data: Data
        do {
            data = try encoder.encode(metadata)
        } catch {
            throw RunRepositoryError.encodingError(metadata.run, error)
        }

        let tempURL = url.appendingPathExtension("tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tempURL, to: url)
        } catch {
            throw RunRepositoryError.fileWriteFailed(url.path, error)
        }
    }

    private func appendToIndex(sessionID: String, entry: RunIndexEntry) throws {
        let indexURL = runsDirectory(sessionID: sessionID).appendingPathComponent("index.json")
        var entries: [RunIndexEntry] = []

        if FileManager.default.fileExists(atPath: indexURL.path) {
            do {
                let data = try Data(contentsOf: indexURL)
                entries = try decoder.decode([RunIndexEntry].self, from: data)
            } catch {
                // Corrupted index — rebuild from this entry
                entries = []
            }
        }

        entries.append(entry)
        try writeIndex(entries, to: indexURL)
    }

    private func updateIndexEntry(sessionID: String, entry: RunIndexEntry) throws {
        let indexURL = runsDirectory(sessionID: sessionID).appendingPathComponent("index.json")

        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            // No index yet — create it
            try writeIndex([entry], to: indexURL)
            return
        }

        var entries: [RunIndexEntry]
        do {
            let data = try Data(contentsOf: indexURL)
            entries = try decoder.decode([RunIndexEntry].self, from: data)
        } catch {
            throw RunRepositoryError.indexCorrupted(indexURL.path)
        }

        if let idx = entries.firstIndex(where: { $0.runID == entry.runID }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }

        try writeIndex(entries, to: indexURL)
    }

    private func writeIndex(_ entries: [RunIndexEntry], to url: URL) throws {
        let data: Data
        do {
            data = try encoder.encode(entries)
        } catch {
            throw RunRepositoryError.fileWriteFailed(url.path, error)
        }

        let tempURL = url.appendingPathExtension("tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tempURL, to: url)
        } catch {
            throw RunRepositoryError.fileWriteFailed(url.path, error)
        }
    }

    private func ensureDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw RunRepositoryError.directoryCreationFailed(url.path, error)
        }
    }
}

// MARK: - InMemoryRunRepository (for testing)

/// In-memory implementation of RunRepository for testing.
public final class InMemoryRunRepository: RunRepository {
    private var runs: [String: AgentRun] = [:]       // runID -> run
    private var sessionIndex: [String: [String]] = [:] // sessionID -> [runID]
    private let lock = NSLock()

    public init() {}

    public func createRun(_ run: AgentRun, in sessionID: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard runs[run.id] == nil else {
            throw RunRepositoryError.alreadyExists(run.id)
        }

        runs[run.id] = run
        sessionIndex[sessionID, default: []].append(run.id)
    }

    public func updateRun(_ run: AgentRun) throws {
        lock.lock()
        defer { lock.unlock() }

        guard runs[run.id] != nil else {
            throw RunRepositoryError.notFound(run.id)
        }

        runs[run.id] = run
    }

    public func getRun(runID: String) throws -> AgentRun? {
        lock.lock()
        defer { lock.unlock() }
        return runs[runID]
    }

    public func listRuns(sessionID: String) throws -> [AgentRun] {
        lock.lock()
        defer { lock.unlock() }

        let runIDs = sessionIndex[sessionID] ?? []
        return runIDs
            .compactMap { runs[$0] }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func listRuns(workspace: String) throws -> [AgentRun] {
        lock.lock()
        defer { lock.unlock() }

        return runs.values
            .sorted { $0.createdAt < $1.createdAt }
    }
}
