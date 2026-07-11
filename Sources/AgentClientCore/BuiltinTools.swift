import Foundation

// MARK: - Built-in Tool Definitions

/// Factory for the 5 built-in tools that were previously inline in APIAgentRuntime.
///
/// These definitions are used by:
/// - ToolRegistry (for discovery and execution)
/// - OpenAI-compatible clients (via `openAIToolDefinitions()`)
public enum BuiltinTools {

    // MARK: - Tool Definitions

    /// All 5 built-in tool definitions.
    public static let allDefinitions: [ToolDefinition] = [
        listFilesDefinition,
        readFileDefinition,
        searchTextDefinition,
        writeFileDefinition,
        runShellCommandDefinition,
    ]

    public static let listFilesDefinition = ToolDefinition(
        name: "list_files",
        displayName: "List Files",
        description: "List files in a directory",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "path": [
                    "type": "string",
                    "description": "The path to the directory to list"
                ] as [String: Any]
            ] as [String: Any]),
            "required": AnyCodable(["path"] as [Any]),
        ],
        riskLevel: .low,
        defaultApprovalPolicy: .allow,
        capabilities: ["read"]
    )

    public static let readFileDefinition = ToolDefinition(
        name: "read_file",
        displayName: "Read File",
        description: "Read the contents of a file",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "path": [
                    "type": "string",
                    "description": "The path to the file to read"
                ] as [String: Any]
            ] as [String: Any]),
            "required": AnyCodable(["path"] as [Any]),
        ],
        riskLevel: .low,
        defaultApprovalPolicy: .allow,
        capabilities: ["read"]
    )

    public static let searchTextDefinition = ToolDefinition(
        name: "search_text",
        displayName: "Search Text",
        description: "Search for text in files",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "query": [
                    "type": "string",
                    "description": "The text to search for"
                ] as [String: Any],
                "path": [
                    "type": "string",
                    "description": "The directory to search in"
                ] as [String: Any],
            ] as [String: Any]),
            "required": AnyCodable(["query"] as [Any]),
        ],
        riskLevel: .low,
        defaultApprovalPolicy: .allow,
        capabilities: ["read"]
    )

    public static let writeFileDefinition = ToolDefinition(
        name: "write_file",
        displayName: "Write File",
        description: "Write content to a file",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "path": [
                    "type": "string",
                    "description": "The path to the file to write"
                ] as [String: Any],
                "content": [
                    "type": "string",
                    "description": "The content to write to the file"
                ] as [String: Any],
            ] as [String: Any]),
            "required": AnyCodable(["path", "content"] as [Any]),
        ],
        riskLevel: .high,
        defaultApprovalPolicy: .ask,
        capabilities: ["write"]
    )

    public static let runShellCommandDefinition = ToolDefinition(
        name: "run_shell_command",
        displayName: "Run Shell Command",
        description: "Run a shell command",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "command": [
                    "type": "string",
                    "description": "The command to run"
                ] as [String: Any]
            ] as [String: Any]),
            "required": AnyCodable(["command"] as [Any]),
        ],
        riskLevel: .critical,
        defaultApprovalPolicy: .ask,
        capabilities: ["execute"]
    )

    // MARK: - Tool Executors

    /// All 5 built-in executors, ready for registration.
    public static func allExecutors() -> [ToolExecutor] {
        [
            ListFilesExecutor(),
            ReadFileExecutor(),
            SearchTextExecutor(),
            WriteFileExecutor(),
            RunShellCommandExecutor(),
        ]
    }

    /// Register all built-in tools in a ToolRegistry.
    public static func registerAll(in registry: ToolRegistry) {
        for definition in allDefinitions {
            let executor = executor(for: definition.name)
            registry.register(tool: definition, executor: executor)
        }
    }

    /// Get the executor for a given tool name.
    static func executor(for toolName: String) -> ToolExecutor {
        switch toolName {
        case "list_files": return ListFilesExecutor()
        case "read_file": return ReadFileExecutor()
        case "search_text": return SearchTextExecutor()
        case "write_file": return WriteFileExecutor()
        case "run_shell_command": return RunShellCommandExecutor()
        default:
            fatalError("No executor for built-in tool: \(toolName)")
        }
    }

    // MARK: - OpenAI Wire Format Conversion

    /// Convert all built-in tool definitions to OpenAI wire format.
    ///
    /// This bridges the new ToolRegistry definitions to the OpenAI-compatible
    /// API format used by OpenAICompatibleClient.
    public static func openAIToolDefinitions() -> [OpenAIToolDefinition] {
        allDefinitions.map { definition in
            // Reconstruct the OpenAI wire format from the ToolDefinition's inputSchema
            var parameters: [String: Any] = [:]
            if let schema = definition.inputSchema {
                parameters = schema.mapValues { $0.value }
            }

            return OpenAIToolDefinition(function: OpenAIFunctionDefinition(
                name: definition.name,
                description: definition.description,
                parameters: parameters
            ))
        }
    }
}

// MARK: - Built-in Tool Executors

/// Executes `list_files` — lists files in a directory.
struct ListFilesExecutor: ToolExecutor {
    let toolName = "list_files"

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        guard let path = call.parameters["path"] else {
            return ToolResult(callID: call.id, success: false, error: "Missing parameter: path")
        }

        let resolvedPath = resolvePath(path, relativeTo: context.workspacePath)
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(atPath: resolvedPath) else {
            return ToolResult(callID: call.id, success: false, error: "Cannot list directory: \(resolvedPath)")
        }

        let listing = contents.sorted().joined(separator: "\n")
        return ToolResult(callID: call.id, success: true, output: listing)
    }
}

/// Executes `read_file` — reads file contents.
struct ReadFileExecutor: ToolExecutor {
    let toolName = "read_file"

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        guard let path = call.parameters["path"] else {
            return ToolResult(callID: call.id, success: false, error: "Missing parameter: path")
        }

        let resolvedPath = resolvePath(path, relativeTo: context.workspacePath)

        guard let content = try? String(contentsOfFile: resolvedPath, encoding: .utf8) else {
            return ToolResult(callID: call.id, success: false, error: "Cannot read file: \(resolvedPath)")
        }

        return ToolResult(callID: call.id, success: true, output: content)
    }
}

/// Executes `search_text` — searches for text in files using grep.
struct SearchTextExecutor: ToolExecutor {
    let toolName = "search_text"

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        guard let query = call.parameters["query"] else {
            return ToolResult(callID: call.id, success: false, error: "Missing parameter: query")
        }

        let searchPath = call.parameters["path"].map {
            resolvePath($0, relativeTo: context.workspacePath)
        } ?? context.workspacePath

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = ["-r", "-n", query, searchPath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                return ToolResult(callID: call.id, success: true, output: output)
            } else {
                return ToolResult(callID: call.id, success: true, output: "No matches found.")
            }
        } catch {
            return ToolResult(callID: call.id, success: false, error: "Search failed: \(error.localizedDescription)")
        }
    }
}

/// Executes `write_file` — writes content to a file.
struct WriteFileExecutor: ToolExecutor {
    let toolName = "write_file"

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        guard let path = call.parameters["path"] else {
            return ToolResult(callID: call.id, success: false, error: "Missing parameter: path")
        }
        guard let content = call.parameters["content"] else {
            return ToolResult(callID: call.id, success: false, error: "Missing parameter: content")
        }

        let resolvedPath = resolvePath(path, relativeTo: context.workspacePath)
        let fileManager = FileManager.default

        // Ensure parent directory exists
        let parentDir = (resolvedPath as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        do {
            try content.write(toFile: resolvedPath, atomically: true, encoding: .utf8)
            return ToolResult(callID: call.id, success: true, output: "File written: \(resolvedPath)")
        } catch {
            return ToolResult(callID: call.id, success: false, error: "Write failed: \(error.localizedDescription)")
        }
    }
}

/// Executes `run_shell_command` — runs a shell command.
struct RunShellCommandExecutor: ToolExecutor {
    let toolName = "run_shell_command"

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        guard let command = call.parameters["command"] else {
            return ToolResult(callID: call.id, success: false, error: "Missing parameter: command")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: context.workspacePath)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let outStr = String(data: outData, encoding: .utf8) ?? ""
            let errStr = String(data: errData, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                return ToolResult(callID: call.id, success: true, output: outStr)
            } else {
                let combined = outStr.isEmpty ? errStr : "\(outStr)\n\(errStr)"
                return ToolResult(callID: call.id, success: false, error: combined)
            }
        } catch {
            return ToolResult(callID: call.id, success: false, error: "Command failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Path Resolution

/// Resolve a path relative to the workspace path.
/// If the path is already absolute, returns it as-is.
private func resolvePath(_ path: String, relativeTo workspace: String) -> String {
    if path.hasPrefix("/") {
        return path
    }
    return (workspace as NSString).appendingPathComponent(path)
}
