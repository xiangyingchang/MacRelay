import XCTest
@testable import AgentClientCore

final class ToolRegistryTests: XCTestCase {

    // MARK: - Helpers

    private func makeRegistry() -> ToolRegistry {
        ToolRegistry()
    }

    private func makeDummyDefinition(
        name: String = "test_tool",
        riskLevel: RiskLevel = .low,
        approvalPolicy: ApprovalPolicy = .allow,
        capabilities: [String] = ["read"],
        requiredParams: [String]? = nil
    ) -> ToolDefinition {
        var schema: [String: AnyCodable]? = nil
        if let required = requiredParams {
            schema = [
                "type": AnyCodable("object"),
                "required": AnyCodable(required.map { AnyCodable($0) }),
            ]
        }
        return ToolDefinition(
            name: name,
            displayName: "Test Tool",
            description: "A test tool",
            inputSchema: schema,
            riskLevel: riskLevel,
            defaultApprovalPolicy: approvalPolicy,
            capabilities: capabilities
        )
    }

    private func makeDummyExecutor(name: String = "test_tool", output: String = "ok") -> ToolExecutor {
        DummyExecutor(toolName: name, output: output)
    }

    // MARK: - Registration and Lookup

    func testRegisterAndLookup() {
        let registry = makeRegistry()
        let def = makeDummyDefinition(name: "my_tool")
        registry.register(tool: def, executor: makeDummyExecutor(name: "my_tool"))

        let found = registry.definition(name: "my_tool")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "my_tool")
        XCTAssertEqual(found?.displayName, "Test Tool")
    }

    func testListTools() {
        let registry = makeRegistry()
        registry.register(tool: makeDummyDefinition(name: "b_tool"), executor: makeDummyExecutor(name: "b_tool"))
        registry.register(tool: makeDummyDefinition(name: "a_tool"), executor: makeDummyExecutor(name: "a_tool"))

        let tools = registry.listTools()
        XCTAssertEqual(tools.count, 2)
        // Should be sorted by name
        XCTAssertEqual(tools[0].name, "a_tool")
        XCTAssertEqual(tools[1].name, "b_tool")
    }

    func testHasTool() {
        let registry = makeRegistry()
        XCTAssertFalse(registry.hasTool(name: "missing"))

        registry.register(tool: makeDummyDefinition(name: "exists"), executor: makeDummyExecutor(name: "exists"))
        XCTAssertTrue(registry.hasTool(name: "exists"))
    }

    func testUnregister() {
        let registry = makeRegistry()
        registry.register(tool: makeDummyDefinition(name: "tool_a"), executor: makeDummyExecutor(name: "tool_a"))
        XCTAssertTrue(registry.hasTool(name: "tool_a"))

        let removed = registry.unregister(name: "tool_a")
        XCTAssertTrue(removed)
        XCTAssertFalse(registry.hasTool(name: "tool_a"))
        XCTAssertNil(registry.definition(name: "tool_a"))
    }

    func testUnregisterNonexistent() {
        let registry = makeRegistry()
        let removed = registry.unregister(name: "nope")
        XCTAssertFalse(removed)
    }

    func testRegisterReplacesExisting() {
        let registry = makeRegistry()
        let def1 = makeDummyDefinition(name: "tool", riskLevel: .low)
        let def2 = makeDummyDefinition(name: "tool", riskLevel: .high)

        registry.register(tool: def1, executor: makeDummyExecutor(name: "tool"))
        registry.register(tool: def2, executor: makeDummyExecutor(name: "tool"))

        XCTAssertEqual(registry.listTools().count, 1)
        XCTAssertEqual(registry.definition(name: "tool")?.riskLevel, .high)
    }

    // MARK: - Unknown Tool Handling

    func testExecuteUnknownTool() async throws {
        let registry = makeRegistry()
        let call = ToolCall(id: "call-1", name: "nonexistent", parameters: [:])
        let context = ToolExecutionContext(workspacePath: "/tmp")

        let result = try await registry.execute(call: call, context: context)

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.error!.contains("nonexistent"))
        XCTAssertEqual(result.callID, "call-1")
    }

    // MARK: - Parameter Validation

    func testMissingRequiredParameter() async throws {
        let registry = makeRegistry()
        let def = makeDummyDefinition(name: "reader", requiredParams: ["path"])
        registry.register(tool: def, executor: makeDummyExecutor(name: "reader"))

        let call = ToolCall(id: "call-2", name: "reader", parameters: [:])
        let context = ToolExecutionContext(workspacePath: "/tmp")

        let result = try await registry.execute(call: call, context: context)

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
        if let error = result.error {
            XCTAssertTrue(error.contains("path"))
        }
    }

    func testRequiredParameterPresent() async throws {
        let registry = makeRegistry()
        let def = makeDummyDefinition(name: "reader", requiredParams: ["path"])
        registry.register(tool: def, executor: makeDummyExecutor(name: "reader", output: "file content"))

        let call = ToolCall(id: "call-3", name: "reader", parameters: ["path": "/some/file"])
        let context = ToolExecutionContext(workspacePath: "/tmp")

        let result = try await registry.execute(call: call, context: context)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "file content")
    }

    func testNoSchemaSkipsValidation() async throws {
        let registry = makeRegistry()
        // No inputSchema → no required params check
        let def = makeDummyDefinition(name: "free_tool", requiredParams: nil)
        registry.register(tool: def, executor: makeDummyExecutor(name: "free_tool", output: "done"))

        let call = ToolCall(id: "call-4", name: "free_tool", parameters: [:])
        let context = ToolExecutionContext(workspacePath: "/tmp")

        let result = try await registry.execute(call: call, context: context)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "done")
    }

    // MARK: - Risk Level Assignment

    func testRiskLevels() {
        XCTAssertEqual(RiskLevel.low, RiskLevel.low)
        XCTAssertNotEqual(RiskLevel.low, RiskLevel.high)

        XCTAssertTrue(RiskLevel.low < RiskLevel.medium)
        XCTAssertTrue(RiskLevel.medium < RiskLevel.high)
        XCTAssertTrue(RiskLevel.high < RiskLevel.critical)
        XCTAssertFalse(RiskLevel.critical < RiskLevel.low)
    }

    func testToolDefinitionsHaveCorrectRiskLevels() {
        XCTAssertEqual(BuiltinTools.listFilesDefinition.riskLevel, .low)
        XCTAssertEqual(BuiltinTools.readFileDefinition.riskLevel, .low)
        XCTAssertEqual(BuiltinTools.searchTextDefinition.riskLevel, .low)
        XCTAssertEqual(BuiltinTools.writeFileDefinition.riskLevel, .high)
        XCTAssertEqual(BuiltinTools.runShellCommandDefinition.riskLevel, .critical)
    }

    func testToolDefinitionsHaveCorrectApprovalPolicies() {
        XCTAssertEqual(BuiltinTools.listFilesDefinition.defaultApprovalPolicy, .allow)
        XCTAssertEqual(BuiltinTools.readFileDefinition.defaultApprovalPolicy, .allow)
        XCTAssertEqual(BuiltinTools.searchTextDefinition.defaultApprovalPolicy, .allow)
        XCTAssertEqual(BuiltinTools.writeFileDefinition.defaultApprovalPolicy, .ask)
        XCTAssertEqual(BuiltinTools.runShellCommandDefinition.defaultApprovalPolicy, .ask)
    }

    func testToolDefinitionsHaveCorrectCapabilities() {
        XCTAssertEqual(BuiltinTools.listFilesDefinition.capabilities, ["read"])
        XCTAssertEqual(BuiltinTools.writeFileDefinition.capabilities, ["write"])
        XCTAssertEqual(BuiltinTools.runShellCommandDefinition.capabilities, ["execute"])
    }

    // MARK: - Execution Success and Failure

    func testExecutionSuccess() async throws {
        let registry = makeRegistry()
        registry.register(
            tool: makeDummyDefinition(name: "succeed"),
            executor: makeDummyExecutor(name: "succeed", output: "result data")
        )

        let call = ToolCall(id: "call-5", name: "succeed", parameters: [:])
        let context = ToolExecutionContext(workspacePath: "/tmp")

        let result = try await registry.execute(call: call, context: context)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "result data")
        XCTAssertNil(result.error)
        XCTAssertEqual(result.callID, "call-5")
    }

    func testExecutionFailure() async throws {
        let registry = makeRegistry()
        registry.register(
            tool: makeDummyDefinition(name: "fail_tool"),
            executor: FailingExecutor(toolName: "fail_tool", errorMessage: "disk full")
        )

        let call = ToolCall(id: "call-6", name: "fail_tool", parameters: [:])
        let context = ToolExecutionContext(workspacePath: "/tmp")

        let result = try await registry.execute(call: call, context: context)

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.error!.contains("disk full"))
    }

    func testExecutorThrowingError() async throws {
        let registry = makeRegistry()
        registry.register(
            tool: makeDummyDefinition(name: "throw_tool"),
            executor: ThrowingExecutor(toolName: "throw_tool")
        )

        let call = ToolCall(id: "call-7", name: "throw_tool", parameters: [:])
        let context = ToolExecutionContext(workspacePath: "/tmp")

        let result = try await registry.execute(call: call, context: context)

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.error!.contains("thrown error"))
    }

    // MARK: - Execution Count Tracking

    func testExecutionCountTracking() async throws {
        let registry = makeRegistry()
        registry.register(
            tool: makeDummyDefinition(name: "counter"),
            executor: makeDummyExecutor(name: "counter")
        )

        XCTAssertEqual(registry.executionCount(for: "counter"), 0)

        let context = ToolExecutionContext(workspacePath: "/tmp")
        let call = ToolCall(id: "c1", name: "counter", parameters: [:])

        _ = try await registry.execute(call: call, context: context)
        XCTAssertEqual(registry.executionCount(for: "counter"), 1)

        _ = try await registry.execute(call: call, context: context)
        _ = try await registry.execute(call: call, context: context)
        XCTAssertEqual(registry.executionCount(for: "counter"), 3)
    }

    func testExecutionCountPerTool() async throws {
        let registry = makeRegistry()
        registry.register(tool: makeDummyDefinition(name: "tool_a"), executor: makeDummyExecutor(name: "tool_a"))
        registry.register(tool: makeDummyDefinition(name: "tool_b"), executor: makeDummyExecutor(name: "tool_b"))

        let context = ToolExecutionContext(workspacePath: "/tmp")

        _ = try await registry.execute(
            call: ToolCall(id: "1", name: "tool_a", parameters: [:]),
            context: context
        )
        _ = try await registry.execute(
            call: ToolCall(id: "2", name: "tool_a", parameters: [:]),
            context: context
        )
        _ = try await registry.execute(
            call: ToolCall(id: "3", name: "tool_b", parameters: [:]),
            context: context
        )

        XCTAssertEqual(registry.executionCount(for: "tool_a"), 2)
        XCTAssertEqual(registry.executionCount(for: "tool_b"), 1)

        let counts = registry.allExecutionCounts()
        XCTAssertEqual(counts["tool_a"], 2)
        XCTAssertEqual(counts["tool_b"], 1)
    }

    func testExecutionCountNotIncrementedOnValidationFailure() async throws {
        let registry = makeRegistry()
        let def = makeDummyDefinition(name: "needs_path", requiredParams: ["path"])
        registry.register(tool: def, executor: makeDummyExecutor(name: "needs_path"))

        let call = ToolCall(id: "bad", name: "needs_path", parameters: [:])
        let context = ToolExecutionContext(workspacePath: "/tmp")

        _ = try await registry.execute(call: call, context: context)

        // Count should NOT increment because validation failed before execution
        XCTAssertEqual(registry.executionCount(for: "needs_path"), 0)
    }

    func testExecutionCountNotIncrementedOnUnknownTool() async throws {
        let registry = makeRegistry()
        let call = ToolCall(id: "unknown", name: "ghost", parameters: [:])
        let context = ToolExecutionContext(workspacePath: "/tmp")

        _ = try await registry.execute(call: call, context: context)

        XCTAssertEqual(registry.executionCount(for: "ghost"), 0)
    }

    // MARK: - ToolResult → RuntimeEvent

    func testSuccessfulResultProducesCompletedEvent() {
        let result = ToolResult(callID: "call-10", success: true, output: "file contents here")
        let event = result.toRuntimeEvent(runtime: .openAI, toolName: "read_file", sessionID: "s1", runID: "r1")

        XCTAssertEqual(event.type, .toolCallCompleted)
        XCTAssertEqual(event.sessionID, "s1")
        XCTAssertEqual(event.runID, "r1")
        XCTAssertEqual(event.runtime, .openAI)

        if case .toolCallCompleted(let name, let output) = event.payload {
            XCTAssertEqual(name, "call-10")
            XCTAssertEqual(output, "file contents here")
        } else {
            XCTFail("Expected toolCallCompleted payload")
        }
    }

    func testFailedResultProducesFailedEvent() {
        let result = ToolResult(callID: "call-11", success: false, error: "permission denied")
        let event = result.toRuntimeEvent(runtime: .mimo, toolName: "write_file", sessionID: "s2")

        XCTAssertEqual(event.type, .toolCallFailed)
        XCTAssertEqual(event.sessionID, "s2")
        XCTAssertNil(event.runID)
        XCTAssertEqual(event.runtime, .mimo)

        if case .toolCallFailed(let name, let error) = event.payload {
            XCTAssertEqual(name, "write_file")
            XCTAssertEqual(error, "permission denied")
        } else {
            XCTFail("Expected toolCallFailed payload")
        }
    }

    func testFailedResultWithNilErrorProducesDefaultMessage() {
        let result = ToolResult(callID: "call-12", success: false)
        let event = result.toRuntimeEvent(runtime: .openAI, toolName: "unknown_tool")

        if case .toolCallFailed(_, let error) = event.payload {
            XCTAssertEqual(error, "Unknown error")
        } else {
            XCTFail("Expected toolCallFailed payload")
        }
    }

    // MARK: - ToolDefinition Codable

    func testToolDefinitionCodable() throws {
        let def = ToolDefinition(
            name: "my_tool",
            displayName: "My Tool",
            description: "Does things",
            inputSchema: ["type": AnyCodable("object")],
            riskLevel: .high,
            defaultApprovalPolicy: .ask,
            capabilities: ["read", "write"]
        )

        let data = try JSONEncoder().encode(def)
        let decoded = try JSONDecoder().decode(ToolDefinition.self, from: data)

        XCTAssertEqual(decoded.name, "my_tool")
        XCTAssertEqual(decoded.displayName, "My Tool")
        XCTAssertEqual(decoded.description, "Does things")
        XCTAssertEqual(decoded.riskLevel, .high)
        XCTAssertEqual(decoded.defaultApprovalPolicy, .ask)
        XCTAssertEqual(decoded.capabilities, ["read", "write"])
        XCTAssertNotNil(decoded.inputSchema)
    }

    // MARK: - ToolCall and ToolResult Codable

    func testToolCallCodable() throws {
        let call = ToolCall(id: "tc-1", name: "read_file", parameters: ["path": "/etc/hosts"])

        let data = try JSONEncoder().encode(call)
        let decoded = try JSONDecoder().decode(ToolCall.self, from: data)

        XCTAssertEqual(decoded, call)
    }

    func testToolResultCodable() throws {
        let result = ToolResult(callID: "tc-1", success: true, output: "contents")

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ToolResult.self, from: data)

        XCTAssertEqual(decoded, result)
    }

    // MARK: - BuiltinTools

    func testBuiltinToolsCount() {
        XCTAssertEqual(BuiltinTools.allDefinitions.count, 5)
    }

    func testRegisterAllBuiltinTools() {
        let registry = makeRegistry()
        BuiltinTools.registerAll(in: registry)

        XCTAssertEqual(registry.listTools().count, 5)
        XCTAssertTrue(registry.hasTool(name: "list_files"))
        XCTAssertTrue(registry.hasTool(name: "read_file"))
        XCTAssertTrue(registry.hasTool(name: "search_text"))
        XCTAssertTrue(registry.hasTool(name: "write_file"))
        XCTAssertTrue(registry.hasTool(name: "run_shell_command"))
    }

    func testOpenAIToolDefinitionsFromBuiltinTools() {
        let openAITools = BuiltinTools.openAIToolDefinitions()

        XCTAssertEqual(openAITools.count, 5)
        let names = openAITools.map(\.function.name).sorted()
        XCTAssertEqual(names, ["list_files", "read_file", "run_shell_command", "search_text", "write_file"])
    }

    // MARK: - ApprovalPolicy and RiskLevel Codable

    func testApprovalPolicyCodable() throws {
        let policies: [ApprovalPolicy] = [.allow, .ask, .deny]
        for policy in policies {
            let data = try JSONEncoder().encode(policy)
            let decoded = try JSONDecoder().decode(ApprovalPolicy.self, from: data)
            XCTAssertEqual(decoded, policy)
        }
    }

    func testRiskLevelCodable() throws {
        let levels: [RiskLevel] = [.low, .medium, .high, .critical]
        for level in levels {
            let data = try JSONEncoder().encode(level)
            let decoded = try JSONDecoder().decode(RiskLevel.self, from: data)
            XCTAssertEqual(decoded, level)
        }
    }

    // MARK: - Execution Context

    func testExecutionContextDefaults() {
        let ctx = ToolExecutionContext(workspacePath: "/workspace")
        XCTAssertEqual(ctx.workspacePath, "/workspace")
        XCTAssertNil(ctx.sessionID)
        XCTAssertNil(ctx.runID)
    }

    func testExecutionContextFull() {
        let ctx = ToolExecutionContext(workspacePath: "/ws", sessionID: "s1", runID: "r1")
        XCTAssertEqual(ctx.workspacePath, "/ws")
        XCTAssertEqual(ctx.sessionID, "s1")
        XCTAssertEqual(ctx.runID, "r1")
    }
}

// MARK: - Test Helpers

/// A dummy executor that returns a fixed output.
private struct DummyExecutor: ToolExecutor {
    let toolName: String
    let output: String

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        ToolResult(callID: call.id, success: true, output: output)
    }
}

/// An executor that always returns a failure result.
private struct FailingExecutor: ToolExecutor {
    let toolName: String
    let errorMessage: String

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        ToolResult(callID: call.id, success: false, error: errorMessage)
    }
}

/// An executor that always throws an error.
private struct ThrowingExecutor: ToolExecutor {
    let toolName: String

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        throw ToolExecutionError.executionFailed("thrown error")
    }
}
