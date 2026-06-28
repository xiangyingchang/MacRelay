import Foundation

/// Manages the `.macrelay/` journal inside the user's workspace directory.
///
/// Directory structure:
/// ```
/// workspace/
/// ├── .macrelay/
/// │   ├── sessions/
/// │   │   ├── 2026-06-28-001.log    ← conversation transcripts
/// │   │   └── 2026-06-28-002.log
/// │   └── memory.md                 ← accumulated project memory
/// ```
@MainActor
final class SessionJournal {
    private let fileManager = FileManager.default

    /// Current workspace path — changes when user picks a new folder.
    var workspacePath: String = ""

    private var sessionLogPath: String = ""
    private var memoryPath: String = ""
    private var sessionSeq = 0
    private var initialized = false

    init() {}

    // MARK: - Setup (lazy: called on first message)

    private func ensureDirectories() {
        guard !workspacePath.isEmpty else { return }
        if initialized { return }
        initialized = true
        let macrelay = workspacePath + "/.macrelay"
        let sessions = macrelay + "/sessions"
        try? fileManager.createDirectory(atPath: macrelay, withIntermediateDirectories: true)
        try? fileManager.createDirectory(atPath: sessions, withIntermediateDirectories: true)
        memoryPath = macrelay + "/memory.md"
        if !fileManager.fileExists(atPath: memoryPath) {
            try? "# MacRelay 工作区记忆\n\n".write(toFile: memoryPath, atomically: true, encoding: .utf8)
        }
        // Determine session sequence number
        let datePrefix = dateString()
        let existing = (try? fileManager.contentsOfDirectory(atPath: sessions)) ?? []
        let maxSeq = existing
            .filter { $0.hasPrefix(datePrefix) }
            .compactMap { name -> Int? in
                let parts = name.dropFirst(datePrefix.count + 1).dropLast(4)
                return Int(parts)
            }
            .max() ?? 0
        sessionSeq = maxSeq + 1
        let filename = "\(datePrefix)-\(String(format: "%03d", sessionSeq)).log"
        sessionLogPath = sessions + "/" + filename
        writeLine("# Session \(filename)")
        writeLine("> Started at \(ISO8601DateFormatter().string(from: Date()))")
        writeLine("")
    }

    // MARK: - Logging (creates directories on first call)

    func logUserMessage(_ text: String) {
        ensureDirectories()
        writeLine("## User")
        writeLine(text)
        writeLine("")
    }

    func logAssistantMessage(_ role: String, _ text: String) {
        ensureDirectories()
        writeLine("## \(role)")
        writeLine(text)
        writeLine("")
    }

    func logSystemEvent(_ event: String) {
        ensureDirectories()
        writeLine("> \(event)")
    }

    /// A previous session loaded from disk.
    struct ArchivedSession {
        let sessionID: String
        let createdAt: Date
        let messages: [(role: String, text: String)]
    }

    /// Load all archived sessions from .macrelay/sessions/.
    func loadArchivedSessions() -> [ArchivedSession] {
        guard !workspacePath.isEmpty else { return [] }
        let sessionsDir = workspacePath + "/.macrelay/sessions"
        guard let files = try? fileManager.contentsOfDirectory(atPath: sessionsDir) else { return [] }

        var sessions: [ArchivedSession] = []
        let sortedFiles = files
            .filter { $0.hasSuffix(".log") }
            .sorted { a, b in
                let aURL = URL(fileURLWithPath: sessionsDir + "/" + a)
                let bURL = URL(fileURLWithPath: sessionsDir + "/" + b)
                let aMod = (try? aURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let bMod = (try? bURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return aMod > bMod
            }
        for file in sortedFiles {
            let sessionID = String(file.dropLast(4)) // remove .log
            let path = sessionsDir + "/" + file
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            // Parse creation time from "> Started at ..."
            var createdAt = Date()
            var messages: [(String, String)] = []
            var currentRole = ""
            var currentText = ""

            for line in content.components(separatedBy: "\n") {
                if line.hasPrefix("> Started at ") {
                    let iso = String(line.dropFirst(13))
                    if let date = ISO8601DateFormatter().date(from: iso) { createdAt = date }
                } else if line.hasPrefix("## ") {
                    if !currentRole.isEmpty && !currentText.trimmingCharacters(in: .whitespaces).isEmpty {
                        messages.append((currentRole, currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                    currentRole = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    currentText = ""
                } else if !line.hasPrefix("#") && !line.hasPrefix("> ") {
                    currentText += line + "\n"
                }
            }
            if !currentRole.isEmpty && !currentText.trimmingCharacters(in: .whitespaces).isEmpty {
                messages.append((currentRole, currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
            }

            sessions.append(ArchivedSession(sessionID: sessionID, createdAt: createdAt, messages: messages))
        }
        return sessions
    }

    /// Load messages for a specific archived session.
    func loadArchivedSessionMessages(sessionID: String) -> [(role: String, text: String)] {
        let sessionsDir = workspacePath + "/.macrelay/sessions"
        let path = sessionsDir + "/" + sessionID + ".log"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }

        var messages: [(String, String)] = []
        var currentRole = ""
        var currentText = ""
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                if !currentRole.isEmpty && !currentText.trimmingCharacters(in: .whitespaces).isEmpty {
                    messages.append((currentRole, currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                currentRole = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentText = ""
            } else if !line.hasPrefix("#") && !line.hasPrefix("> ") {
                currentText += line + "\n"
            }
        }
        if !currentRole.isEmpty && !currentText.trimmingCharacters(in: .whitespaces).isEmpty {
            messages.append((currentRole, currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return messages
    }

    /// Delete an archived session log from disk.
    func deleteArchivedSession(sessionID: String) {
        guard !workspacePath.isEmpty else { return }
        let path = workspacePath + "/.macrelay/sessions/" + sessionID + ".log"
        try? fileManager.removeItem(atPath: path)
    }

    /// Append a summary of today's work to memory.md.
    func appendMemory(_ text: String) {
        guard !memoryPath.isEmpty else { return }
        let date = dateString()
        let entry = "\n---\n### \(date)\n\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        if let data = entry.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: memoryPath)) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
    }

    // MARK: - Private

    private func writeLine(_ text: String) {
        guard !sessionLogPath.isEmpty else { return }
        let line = text + "\n"
        if let data = line.data(using: .utf8) {
            if fileManager.fileExists(atPath: sessionLogPath) {
                if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: sessionLogPath)) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? line.write(toFile: sessionLogPath, atomically: true, encoding: .utf8)
            }
        }
    }

    private func dateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
