import Foundation

public struct CodexCLIDetection: Codable, Equatable {
    public var isInstalled: Bool
    public var executablePath: String?
    public var version: String?
    public var errorMessage: String?

    public init(
        isInstalled: Bool,
        executablePath: String? = nil,
        version: String? = nil,
        errorMessage: String? = nil
    ) {
        self.isInstalled = isInstalled
        self.executablePath = executablePath
        self.version = version
        self.errorMessage = errorMessage
    }
}

public enum CodexCLIDetector {
    public static func detect(
        candidatePaths: [String] = defaultCandidatePaths,
        environmentPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        includeVersion: Bool = true
    ) -> CodexCLIDetection {
        guard let executablePath = findExecutable(
            candidatePaths: candidatePaths,
            environmentPath: environmentPath
        ) else {
            return CodexCLIDetection(
                isInstalled: false,
                errorMessage: "Codex CLI executable was not found in known locations or PATH."
            )
        }

        return CodexCLIDetection(
            isInstalled: true,
            executablePath: executablePath,
            version: includeVersion ? version(for: executablePath) : nil
        )
    }

    public static let defaultCandidatePaths = [
        "/Users/haoshifasheng/.npm-global/bin/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex"
    ]

    public static func codexProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let fallbackPath = [
            "/Users/haoshifasheng/.npm-global/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")

        let currentPath = environment["PATH"] ?? ""
        environment["PATH"] = currentPath.isEmpty ? fallbackPath : "\(fallbackPath):\(currentPath)"
        return environment
    }

    private static func findExecutable(candidatePaths: [String], environmentPath: String) -> String? {
        let fileManager = FileManager.default
        for path in candidatePaths where fileManager.isExecutableFile(atPath: path) {
            return path
        }

        for directory in environmentPath.split(separator: ":").map(String.init) {
            let path = URL(fileURLWithPath: directory).appendingPathComponent("codex").path
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private static func version(for executablePath: String) -> String? {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--version"]
        process.environment = codexProcessEnvironment()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let outputText, !outputText.isEmpty {
            return outputText
        }

        return String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
