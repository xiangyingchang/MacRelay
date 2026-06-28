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
