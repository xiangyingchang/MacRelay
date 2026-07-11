import Foundation
@testable import AgentClientCore

/// Loads RuntimeEvent fixtures from JSONL files.
/// Each line in a JSONL file is one RuntimeEvent.
///
/// Usage:
///   let events = try FixtureLoader.loadFixture("normal_coding_run")
///   let snapshot = FixtureLoader.reduceToSnapshot(events)
enum FixtureLoader {
    /// Load a fixture JSONL file from Tests/Fixtures/ by name (without extension).
    static func loadFixture(_ name: String) throws -> [RuntimeEvent] {
        // Try to find the fixture file relative to the package root
        let fixturePath = findFixturePath(name)
        guard let data = FileManager.default.contents(atPath: fixturePath) else {
            throw FixtureError.fileNotFound(name)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw FixtureError.invalidEncoding(name)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var events: [RuntimeEvent] = []
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for (index, line) in lines.enumerated() {
            guard let lineData = line.data(using: .utf8) else {
                throw FixtureError.invalidLine(index, name)
            }
            do {
                let event = try decoder.decode(RuntimeEvent.self, from: lineData)
                events.append(event)
            } catch {
                throw FixtureError.decodingError(index, name, error)
            }
        }

        return events
    }

    /// Reduce an array of RuntimeEvents to a SessionSnapshot using the SessionStateReducer.
    /// This is the canonical way to build a snapshot from a fixture for testing.
    static func reduceToSnapshot(_ events: [RuntimeEvent]) -> SessionSnapshot {
        let reducer = SessionStateReducer()
        var snapshot = SessionSnapshot()

        for event in events {
            // Handle approval resolution directly since it's not in actions(from:)
            if case let .approvalResolved(requestID, decision) = event.payload {
                reducer.reduce(&snapshot, action: .approvalResolved(requestID: requestID, decision: decision))
                continue
            }

            // Handle run lifecycle events directly
            if case let .turnStarted(turnID, input) = event.payload {
                reducer.reduce(&snapshot, action: .runStarted(runID: turnID ?? UUID().uuidString, input: input, runtime: event.runtime))
            }

            let actions = reducer.actions(from: eventToCodexEvent(event))
            for action in actions {
                reducer.reduce(&snapshot, action: action)
            }
        }

        return snapshot
    }

    /// Convert a RuntimeEvent back to a CodexAppServerEvent for the reducer.
    /// This is a lossy conversion — only fields needed by the reducer are preserved.
    private static func eventToCodexEvent(_ event: RuntimeEvent) -> CodexAppServerEvent {
        switch event.type {
        case .sessionStarted:
            if case let .sessionStarted(sessionID, cwd) = event.payload {
                var params: [String: Any] = ["id": sessionID]
                if let cwd { params["cwd"] = cwd }
                params["status"] = ["type": "active"]
                return .notification(method: "thread/started", params: params)
            }
            return .raw("")

        case .turnStarted:
            if case let .turnStarted(turnID, input) = event.payload {
                var params: [String: Any] = [:]
                if let turnID { params["turn_id"] = turnID }
                if let input { params["input"] = input }
                return .notification(method: "turn/started", params: params)
            }
            return .raw("")

        case .turnCompleted:
            if case let .turnCompleted(turnID) = event.payload {
                var params: [String: Any] = [:]
                if let turnID { params["turn_id"] = turnID }
                return .notification(method: "turn/completed", params: params)
            }
            return .raw("")

        case .turnError:
            if case let .turnError(turnID, message) = event.payload {
                // Convert to error notification so the reducer processes it
                var errorDict: [String: Any] = ["message": message]
                if let turnID { errorDict["turn_id"] = turnID }
                return .notification(method: "error", params: ["error": errorDict])
            }
            return .raw("")

        case .assistantDelta:
            if case let .assistantDelta(text) = event.payload {
                return .notification(method: "item/agentMessage/delta", params: ["delta": text])
            }
            return .raw("")

        case .approvalRequested:
            if case let .approvalRequested(requestID, tool, command, riskLevel) = event.payload {
                var params: [String: Any] = [:]
                if let command { params["command"] = command }
                if let riskLevel { params["riskLevel"] = riskLevel }
                // CodexApprovalRequest requires method to contain "requestApproval"
                return .serverRequest(id: requestID, method: "requestApproval_\(tool)", params: params)
            }
            return .raw("")

        case .approvalResolved:
            if case let .approvalResolved(requestID, decision) = event.payload {
                // The reducer handles approval.resolve via serverRequest
                // but we need to match the pending approval's requestID
                return .serverRequest(id: requestID, method: "approval.resolve", params: ["decision": decision])
            }
            return .raw("")

        case .fileChangeDetected:
            if case let .fileChange(path, changeKind) = event.payload {
                // CodexFileChangeUpdated requires method to be "item/started" or "item/completed"
                // with a specific item structure
                let item: [String: Any] = [
                    "type": "fileChange",
                    "path": path,
                    "kind": changeKind,
                    "status": changeKind
                ]
                return .notification(method: "item/completed", params: ["item": item])
            }
            return .raw("")

        case .diffUpdated:
            if case let .diffUpdated(files) = event.payload {
                return .notification(method: "diff.updated", params: ["changedFiles": files])
            }
            return .raw("")

        case .error:
            if case let .error(message, code) = event.payload {
                var errorDict: [String: Any] = ["message": message]
                if let code { errorDict["codexErrorInfo"] = code }
                return .notification(method: "error", params: ["error": errorDict])
            }
            return .raw("")

        case .sessionStopped:
            return .notification(method: "thread/stopped", params: [:])

        case .sessionSelected:
            return .raw("")

        case .exited:
            #if os(macOS)
            return .exit(code: 0, reason: .exit)
            #else
            return .raw("")
            #endif

        case .settingsUpdated:
            if case let .settingsUpdated(model, effort) = event.payload {
                var settings: [String: Any] = [:]
                if let model { settings["model"] = model }
                if let effort { settings["effort"] = effort }
                return .notification(method: "thread/settings/updated", params: ["settings": settings])
            }
            return .raw("")

        case .assistantMessageCompleted,
             .toolCallRequested, .toolCallCompleted, .toolCallFailed,
             .unknown:
            return .raw("")
        }
    }

    /// Find the fixture file path by searching common locations.
    private static func findFixturePath(_ name: String) -> String {
        let filename = "\(name).jsonl"

        // Try relative to the test file's directory
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
        let fixturePath = "\(testDir)/../Fixtures/\(filename)"
        if FileManager.default.fileExists(atPath: fixturePath) {
            return fixturePath
        }

        // Try relative to package root
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().path
        let rootFixturePath = "\(packageRoot)/Tests/Fixtures/\(filename)"
        if FileManager.default.fileExists(atPath: rootFixturePath) {
            return rootFixturePath
        }

        // Try current directory
        let cwdPath = FileManager.default.currentDirectoryPath + "/Tests/Fixtures/\(filename)"
        if FileManager.default.fileExists(atPath: cwdPath) {
            return cwdPath
        }

        return fixturePath // Return the first path for error reporting
    }
}

/// Errors that can occur when loading fixtures.
enum FixtureError: Error, LocalizedError {
    case fileNotFound(String)
    case invalidEncoding(String)
    case invalidLine(Int, String)
    case decodingError(Int, String, Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let name):
            return "Fixture file not found: \(name).jsonl"
        case .invalidEncoding(let name):
            return "Invalid encoding in fixture file: \(name).jsonl"
        case .invalidLine(let line, let name):
            return "Invalid JSON on line \(line + 1) in \(name).jsonl"
        case .decodingError(let line, let name, let error):
            return "Decoding error on line \(line + 1) in \(name).jsonl: \(error.localizedDescription)"
        }
    }
}
