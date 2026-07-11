import Foundation

// MARK: - RunMetadataStore Protocol

/// Abstraction for persisting run metadata to disk.
///
/// Business code should depend on this protocol instead of directly
/// operating on files. This enables testing with in-memory implementations.
public protocol RunMetadataStore: Sendable {
    /// Save run metadata to disk.
    func save(_ metadata: RunMetadata) throws

    /// Load run metadata by runID.
    func load(runID: String) throws -> RunMetadata?

    /// Update an existing run's metadata (merge with saved data).
    func update(runID: String, mutate: (inout RunMetadata) -> Void) throws

    /// List all run metadata for a given session.
    func listRuns(sessionID: String) throws -> [RunMetadata]

    /// Delete run metadata.
    func delete(runID: String) throws

    /// Check if metadata exists for a run.
    func exists(runID: String) -> Bool
}

// MARK: - RunMetadataStore Error

public enum RunMetadataStoreError: Error, LocalizedError {
    case notFound(String)
    case encodingError(RunMetadata, Error)
    case decodingError(String, Error)
    case directoryCreationFailed(String, Error)
    case fileWriteFailed(String, Error)

    public var errorDescription: String? {
        switch self {
        case .notFound(let runID):
            return "Run metadata not found: \(runID)"
        case .encodingError(_, let error):
            return "Failed to encode run metadata: \(error.localizedDescription)"
        case .decodingError(let path, let error):
            return "Failed to decode run metadata at \(path): \(error.localizedDescription)"
        case .directoryCreationFailed(let path, let error):
            return "Failed to create directory \(path): \(error.localizedDescription)"
        case .fileWriteFailed(let path, let error):
            return "Failed to write \(path): \(error.localizedDescription)"
        }
    }
}

// MARK: - FileRunMetadataStore

/// Persists `RunMetadata` as JSON files.
///
/// Directory structure:
///   .macrelay/sessions/{runID}/metadata.json
///
/// Design goals:
/// - Crash safe — write to temp file then rename
/// - Thread-safe — uses NSLock for concurrent access
/// - Forward compatible — `version` field enables schema migration
public final class FileRunMetadataStore: RunMetadataStore {
    private let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

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

    // MARK: - RunMetadataStore

    public func save(_ metadata: RunMetadata) throws {
        lock.lock()
        defer { lock.unlock() }

        let dir = baseDirectory.appendingPathComponent(metadata.run.id)
        try ensureDirectory(dir)

        let fileURL = dir.appendingPathComponent("metadata.json")
        let data: Data
        do {
            data = try encoder.encode(metadata)
        } catch {
            throw RunMetadataStoreError.encodingError(metadata, error)
        }

        // Atomic write: temp file + rename
        let tempURL = fileURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            // Remove existing file before rename
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        } catch {
            throw RunMetadataStoreError.fileWriteFailed(fileURL.path, error)
        }
    }

    public func load(runID: String) throws -> RunMetadata? {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = baseDirectory
            .appendingPathComponent(runID)
            .appendingPathComponent("metadata.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(RunMetadata.self, from: data)
        } catch {
            throw RunMetadataStoreError.decodingError(fileURL.path, error)
        }
    }

    public func update(runID: String, mutate: (inout RunMetadata) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        guard var metadata = try loadLocked(runID: runID) else {
            throw RunMetadataStoreError.notFound(runID)
        }

        mutate(&metadata)

        let dir = baseDirectory.appendingPathComponent(runID)
        try ensureDirectory(dir)

        let fileURL = dir.appendingPathComponent("metadata.json")
        let data: Data
        do {
            data = try encoder.encode(metadata)
        } catch {
            throw RunMetadataStoreError.encodingError(metadata, error)
        }

        let tempURL = fileURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        } catch {
            throw RunMetadataStoreError.fileWriteFailed(fileURL.path, error)
        }
    }

    public func listRuns(sessionID: String) throws -> [RunMetadata] {
        lock.lock()
        defer { lock.unlock() }

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
            let metadataURL = dir.appendingPathComponent("metadata.json")
            guard FileManager.default.fileExists(atPath: metadataURL.path) else { continue }
            do {
                let data = try Data(contentsOf: metadataURL)
                let metadata = try decoder.decode(RunMetadata.self, from: data)
                if metadata.sessionID == sessionID {
                    results.append(metadata)
                }
            } catch {
                // Skip corrupted entries
                continue
            }
        }

        return results.sorted { $0.run.createdAt < $1.run.createdAt }
    }

    public func delete(runID: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let dir = baseDirectory.appendingPathComponent(runID)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
    }

    public func exists(runID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = baseDirectory
            .appendingPathComponent(runID)
            .appendingPathComponent("metadata.json")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: - Private

    /// Load without acquiring lock (caller must hold lock).
    private func loadLocked(runID: String) throws -> RunMetadata? {
        let fileURL = baseDirectory
            .appendingPathComponent(runID)
            .appendingPathComponent("metadata.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(RunMetadata.self, from: data)
    }

    private func ensureDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw RunMetadataStoreError.directoryCreationFailed(url.path, error)
        }
    }
}

// MARK: - In-Memory RunMetadataStore (for testing)

/// In-memory implementation of RunMetadataStore for testing.
public final class InMemoryRunMetadataStore: RunMetadataStore {
    private var store: [String: RunMetadata] = [:]
    private let lock = NSLock()

    public init() {}

    public func save(_ metadata: RunMetadata) throws {
        lock.lock()
        defer { lock.unlock() }
        store[metadata.run.id] = metadata
    }

    public func load(runID: String) throws -> RunMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return store[runID]
    }

    public func update(runID: String, mutate: (inout RunMetadata) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard var metadata = store[runID] else {
            throw RunMetadataStoreError.notFound(runID)
        }
        mutate(&metadata)
        store[runID] = metadata
    }

    public func listRuns(sessionID: String) throws -> [RunMetadata] {
        lock.lock()
        defer { lock.unlock() }
        return store.values
            .filter { $0.sessionID == sessionID }
            .sorted { $0.run.createdAt < $1.run.createdAt }
    }

    public func delete(runID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: runID)
    }

    public func exists(runID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return store[runID] != nil
    }
}
