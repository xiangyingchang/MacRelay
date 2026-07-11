import Foundation

// MARK: - TraceStore Protocol

/// Abstraction for trace persistence.
///
/// Business code should depend on this protocol instead of directly
/// operating on files. This enables testing with in-memory implementations.
public protocol TraceStore: Sendable {
    /// Append a single RuntimeEvent to the trace.
    func append(_ event: RuntimeEvent) throws

    /// Append multiple RuntimeEvents to the trace.
    func append(contentsOf events: [RuntimeEvent]) throws

    /// Read all events from the trace.
    func readAll() throws -> [RuntimeEvent]

    /// Read events after a given sequence number.
    func read(afterSeq: UInt64) throws -> [RuntimeEvent]

    /// The runID this trace belongs to.
    var runID: String { get }

    /// The sessionID this trace belongs to.
    var sessionID: String? { get }

    /// Number of events in the trace.
    var count: Int { get throws }
}

// MARK: - TraceStore Error

public enum TraceStoreError: Error, LocalizedError {
    case fileNotFound(String)
    case invalidEncoding(String)
    case decodingError(Int, String, Error)
    case encodingError(RuntimeEvent, Error)
    case directoryCreationFailed(String, Error)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Trace file not found: \(path)"
        case .invalidEncoding(let path):
            return "Invalid encoding in trace file: \(path)"
        case .decodingError(let line, let path, let error):
            return "Decoding error on line \(line + 1) in \(path): \(error.localizedDescription)"
        case .encodingError(let event, let error):
            return "Encoding error for event \(event.id): \(error.localizedDescription)"
        case .directoryCreationFailed(let path, let error):
            return "Failed to create directory \(path): \(error.localizedDescription)"
        }
    }
}
