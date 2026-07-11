import XCTest
@testable import AgentClientCore

final class ApprovalPolicyTests: XCTestCase {

    // MARK: - Helpers

    private func makeEngine() -> ApprovalPolicyEngine {
        ApprovalPolicyEngine()
    }

    private func makeTool(
        name: String = "test_tool",
        riskLevel: RiskLevel = .low,
        defaultPolicy: ApprovalPolicy = .allow
    ) -> ToolDefinition {
        ToolDefinition(
            name: name,
            displayName: "Test Tool",
            description: "A test tool",
            riskLevel: riskLevel,
            defaultApprovalPolicy: defaultPolicy,
            capabilities: ["read"]
        )
    }

    private func makeCall(name: String = "test_tool", id: String = "call-1") -> ToolCall {
        ToolCall(id: id, name: name, parameters: [:])
    }

    private func makeContext(workspace: String = "/workspace") -> ToolExecutionContext {
        ToolExecutionContext(workspacePath: workspace)
    }

    private func makeRegistry(
        policyEngine: ApprovalPolicyEngine? = nil
    ) -> (ToolRegistry, DummyExecutor) {
        let executor = DummyExecutor(toolName: "test_tool", output: "ok")
        let registry = ToolRegistry(policyEngine: policyEngine)
        return (registry, executor)
    }

    // MARK: - Allow / Ask / Deny Decisions

    func testAllowDecisionFromDefaultPolicy() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .allow)
        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .allow)
        XCTAssertEqual(result.rule, "tool_default")
    }

    func testAskDecisionFromDefaultPolicy() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .ask)
        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .ask)
        XCTAssertEqual(result.rule, "tool_default")
    }

    func testDenyDecisionFromDefaultPolicy() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .deny)
        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .deny)
        XCTAssertEqual(result.rule, "tool_default")
    }

    // MARK: - Policy Priority: Session > Workspace > Global > Default

    func testSessionOverrideOverridesDefault() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .allow)
        engine.addSessionOverride(tool: "test_tool", decision: .alwaysDeny)

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .deny)
        XCTAssertEqual(result.rule, "session_override")
    }

    func testSessionOverrideOverridesGlobal() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .deny)
        engine.addGlobalRule(PolicyRule(
            toolPattern: "test_tool",
            policy: .allow,
            reason: "Global allow"
        ))
        engine.addSessionOverride(tool: "test_tool", decision: .alwaysDeny)

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .deny)
        XCTAssertEqual(result.rule, "session_override")
    }

    func testSessionOverrideOverridesWorkspace() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .deny)
        engine.addWorkspaceRule(
            PolicyRule(toolPattern: "test_tool", policy: .allow, reason: "Workspace allow"),
            workspace: "/workspace"
        )
        engine.addSessionOverride(tool: "test_tool", decision: .alwaysDeny)

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .deny)
        XCTAssertEqual(result.rule, "session_override")
    }

    func testWorkspaceOverridesGlobal() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .deny)
        engine.addGlobalRule(PolicyRule(
            toolPattern: "test_tool",
            policy: .deny,
            reason: "Global deny"
        ))
        engine.addWorkspaceRule(
            PolicyRule(toolPattern: "test_tool", policy: .allow, reason: "Workspace allow"),
            workspace: "/workspace"
        )

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .allow)
        XCTAssertEqual(result.rule, "workspace_rule")
    }

    func testGlobalOverridesDefault() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .deny)
        engine.addGlobalRule(PolicyRule(
            toolPattern: "test_tool",
            policy: .allow,
            reason: "Global allow"
        ))

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .allow)
        XCTAssertEqual(result.rule, "global_rule")
    }

    // MARK: - alwaysAllow for Low-Risk Tools

    func testAlwaysAllowLowRiskTool() {
        let engine = makeEngine()
        let tool = makeTool(riskLevel: .low, defaultPolicy: .ask)
        engine.addSessionOverride(tool: "test_tool", decision: .alwaysAllow)

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .allow)
        XCTAssertEqual(result.rule, "session_override")
    }

    func testAlwaysAllowMediumRiskTool() {
        let engine = makeEngine()
        let tool = makeTool(riskLevel: .medium, defaultPolicy: .ask)
        engine.addSessionOverride(tool: "test_tool", decision: .alwaysAllow)

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .allow)
    }

    func testAlwaysAllowHighRiskTool() {
        let engine = makeEngine()
        let tool = makeTool(riskLevel: .high, defaultPolicy: .ask)
        engine.addSessionOverride(tool: "test_tool", decision: .alwaysAllow)

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .allow)
    }

    // MARK: - alwaysDeny for Dangerous Tools

    func testAlwaysDenyBlocksTool() {
        let engine = makeEngine()
        let tool = makeTool(riskLevel: .high, defaultPolicy: .allow)
        engine.addSessionOverride(tool: "test_tool", decision: .alwaysDeny)

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .deny)
    }

    func testRejectBlocksTool() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .allow)
        engine.addSessionOverride(tool: "test_tool", decision: .reject)

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .deny)
    }

    // MARK: - Critical Tools Always Require Approval

    func testCriticalToolNeverAutoAllowedByDefault() {
        let engine = makeEngine()
        let tool = makeTool(riskLevel: .critical, defaultPolicy: .ask)
        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        // Default policy is "ask" for critical tools
        XCTAssertEqual(result.decision, .ask)
    }

    func testCriticalToolAlwaysAllowDowngradedToAsk() {
        let engine = makeEngine()
        let tool = makeTool(riskLevel: .critical, defaultPolicy: .ask)
        engine.addSessionOverride(tool: "test_tool", decision: .alwaysAllow)

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        // Even alwaysAllow is downgraded to ask for critical tools
        XCTAssertEqual(result.decision, .ask)
        XCTAssertEqual(result.rule, "session_override")
    }

    func testCriticalToolAllowOnceDowngradedToAsk() {
        let engine = makeEngine()
        let tool = makeTool(riskLevel: .critical, defaultPolicy: .ask)
        engine.addSessionOverride(tool: "test_tool", decision: .allowOnce)

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .ask)
    }

    func testCriticalToolGlobalAllowDowngradedToAsk() {
        let engine = makeEngine()
        let tool = makeTool(riskLevel: .critical, defaultPolicy: .ask)
        engine.addGlobalRule(PolicyRule(
            toolPattern: "test_tool",
            policy: .allow,
            reason: "Global allow for critical tool"
        ))

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .ask)
        XCTAssertEqual(result.rule, "global_rule")
    }

    func testCriticalToolWorkspaceAllowDowngradedToAsk() {
        let engine = makeEngine()
        let tool = makeTool(riskLevel: .critical, defaultPolicy: .ask)
        engine.addWorkspaceRule(
            PolicyRule(toolPattern: "test_tool", policy: .allow, reason: "Workspace allow"),
            workspace: "/workspace"
        )

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .ask)
        XCTAssertEqual(result.rule, "workspace_rule")
    }

    func testCriticalToolAlwaysDenyStillDenies() {
        let engine = makeEngine()
        let tool = makeTool(riskLevel: .critical, defaultPolicy: .ask)
        engine.addSessionOverride(tool: "test_tool", decision: .alwaysDeny)

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())

        XCTAssertEqual(result.decision, .deny)
    }

    // MARK: - Different Workspaces Have Different Policies

    func testWorkspacePolicyIsolation() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .deny)

        engine.addWorkspaceRule(
            PolicyRule(toolPattern: "test_tool", policy: .allow, reason: "Allow in ws1"),
            workspace: "/workspace1"
        )
        engine.addWorkspaceRule(
            PolicyRule(toolPattern: "test_tool", policy: .deny, reason: "Deny in ws2"),
            workspace: "/workspace2"
        )

        let result1 = engine.evaluate(
            tool: tool,
            call: makeCall(),
            context: makeContext(workspace: "/workspace1")
        )
        XCTAssertEqual(result1.decision, .allow)
        XCTAssertEqual(result1.rule, "workspace_rule")

        let result2 = engine.evaluate(
            tool: tool,
            call: makeCall(),
            context: makeContext(workspace: "/workspace2")
        )
        XCTAssertEqual(result2.decision, .deny)
        XCTAssertEqual(result2.rule, "workspace_rule")

        // Unmatched workspace falls through to default
        let result3 = engine.evaluate(
            tool: tool,
            call: makeCall(),
            context: makeContext(workspace: "/workspace3")
        )
        XCTAssertEqual(result3.decision, .deny)
        XCTAssertEqual(result3.rule, "tool_default")
    }

    // MARK: - Glob Pattern Matching

    func testGlobPatternMatching() {
        let engine = makeEngine()
        engine.addGlobalRule(PolicyRule(
            toolPattern: "write_*",
            policy: .deny,
            reason: "Deny all write tools"
        ))

        let writeTool = makeTool(name: "write_file")
        let readTool = makeTool(name: "read_file")

        let writeResult = engine.evaluate(tool: writeTool, call: makeCall(name: "write_file"), context: makeContext())
        XCTAssertEqual(writeResult.decision, .deny)
        XCTAssertEqual(writeResult.rule, "global_rule")

        let readResult = engine.evaluate(tool: readTool, call: makeCall(name: "read_file"), context: makeContext())
        XCTAssertEqual(readResult.decision, .allow) // Falls through to default
        XCTAssertEqual(readResult.rule, "tool_default")
    }

    func testWildcardPatternMatchesAll() {
        let engine = makeEngine()
        engine.addGlobalRule(PolicyRule(
            toolPattern: "*",
            riskLevel: .high,
            policy: .deny,
            reason: "Deny all high-risk tools"
        ))

        let highRisk = makeTool(name: "dangerous", riskLevel: .high)
        let lowRisk = makeTool(name: "safe", riskLevel: .low)

        let highResult = engine.evaluate(tool: highRisk, call: makeCall(name: "dangerous"), context: makeContext())
        XCTAssertEqual(highResult.decision, .deny)

        let lowResult = engine.evaluate(tool: lowRisk, call: makeCall(name: "safe"), context: makeContext())
        XCTAssertEqual(lowResult.decision, .allow) // Default, not matched by risk filter
    }

    func testRiskLevelFilterInRule() {
        let engine = makeEngine()
        engine.addGlobalRule(PolicyRule(
            toolPattern: "*",
            riskLevel: .medium,
            policy: .deny,
            reason: "Deny medium-risk tools"
        ))

        let mediumTool = makeTool(name: "med", riskLevel: .medium)
        let highTool = makeTool(name: "high", riskLevel: .high)

        let medResult = engine.evaluate(tool: mediumTool, call: makeCall(name: "med"), context: makeContext())
        XCTAssertEqual(medResult.decision, .deny)

        // High-risk tool not matched because rule filters on .medium only
        let highResult = engine.evaluate(tool: highTool, call: makeCall(name: "high"), context: makeContext())
        XCTAssertEqual(highResult.decision, .allow)
    }

    // MARK: - RuntimeEvent Generation

    func testPolicyEvaluatedEventCreation() {
        let result = PolicyEvaluationResult(
            decision: .allow,
            rule: "tool_default",
            reason: "Default allow"
        )
        let event = ApprovalPolicyEngine.makePolicyEvaluatedEvent(
            toolName: "read_file",
            result: result,
            runtime: .claudeCode,
            sessionID: "s1",
            runID: "r1"
        )

        XCTAssertEqual(event.type, .approvalRequested)
        XCTAssertEqual(event.sessionID, "s1")
        XCTAssertEqual(event.runID, "r1")
        XCTAssertEqual(event.runtime, .claudeCode)

        if case .generic(let method, let params) = event.payload {
            XCTAssertEqual(method, "policy.evaluated")
            XCTAssertEqual(params?["tool"], "read_file")
            XCTAssertEqual(params?["decision"], "allow")
            XCTAssertEqual(params?["rule"], "tool_default")
            XCTAssertEqual(params?["reason"], "Default allow")
        } else {
            XCTFail("Expected generic payload")
        }
    }

    func testApprovalRequestedEventCreation() {
        let event = ApprovalPolicyEngine.makeApprovalRequestedEvent(
            requestID: 42,
            toolName: "write_file",
            riskLevel: .high,
            runtime: .openAI,
            sessionID: "s2",
            runID: "r2"
        )

        XCTAssertEqual(event.type, .approvalRequested)
        XCTAssertEqual(event.sessionID, "s2")
        XCTAssertEqual(event.runID, "r2")
        XCTAssertEqual(event.runtime, .openAI)

        if case .approvalRequested(let rid, let tool, let cmd, let risk) = event.payload {
            XCTAssertEqual(rid, 42)
            XCTAssertEqual(tool, "write_file")
            XCTAssertNil(cmd)
            XCTAssertEqual(risk, "high")
        } else {
            XCTFail("Expected approvalRequested payload")
        }
    }

    func testApprovalResolvedEventCreation() {
        let event = ApprovalPolicyEngine.makeApprovalResolvedEvent(
            requestID: 42,
            decision: .allowOnce,
            runtime: .mimo,
            sessionID: "s3"
        )

        XCTAssertEqual(event.type, .approvalResolved)
        XCTAssertEqual(event.sessionID, "s3")
        XCTAssertEqual(event.runtime, .mimo)

        if case .approvalResolved(let rid, let decision) = event.payload {
            XCTAssertEqual(rid, 42)
            XCTAssertEqual(decision, "allowOnce")
        } else {
            XCTFail("Expected approvalResolved payload")
        }
    }

    // MARK: - Codable Round-Trip for PolicyRule

    func testPolicyRuleCodable() throws {
        let rule = PolicyRule(
            toolPattern: "write_*",
            workspacePath: "/workspace",
            riskLevel: .high,
            policy: .deny,
            reason: "Deny all writes in workspace"
        )

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(PolicyRule.self, from: data)

        XCTAssertEqual(decoded, rule)
        XCTAssertEqual(decoded.toolPattern, "write_*")
        XCTAssertEqual(decoded.workspacePath, "/workspace")
        XCTAssertEqual(decoded.riskLevel, .high)
        XCTAssertEqual(decoded.policy, .deny)
        XCTAssertEqual(decoded.reason, "Deny all writes in workspace")
    }

    func testPolicyRuleCodableNilOptionals() throws {
        let rule = PolicyRule(
            toolPattern: "*",
            policy: .allow,
            reason: "Allow all"
        )

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(PolicyRule.self, from: data)

        XCTAssertEqual(decoded, rule)
        XCTAssertNil(decoded.workspacePath)
        XCTAssertNil(decoded.riskLevel)
    }

    func testApprovalDecisionCodable() throws {
        let decisions: [ApprovalDecision] = [.allowOnce, .alwaysAllow, .reject, .alwaysDeny]
        for decision in decisions {
            let data = try JSONEncoder().encode(decision)
            let decoded = try JSONDecoder().decode(ApprovalDecision.self, from: data)
            XCTAssertEqual(decoded, decision)
        }
    }

    // MARK: - ToolRegistry Integration

    func testRegistryAllowExecution() async throws {
        let engine = makeEngine()
        let (registry, executor) = makeRegistry(policyEngine: engine)
        registry.register(
            tool: makeTool(defaultPolicy: .allow),
            executor: executor
        )

        let result = try await registry.executeWithApproval(
            call: makeCall(),
            context: makeContext()
        )

        XCTAssertEqual(result.status, .allowed)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "ok")
        XCTAssertEqual(result.evaluation.decision, .allow)
        XCTAssertEqual(result.evaluation.rule, "tool_default")
    }

    func testRegistryDenyExecution() async throws {
        let engine = makeEngine()
        let (registry, executor) = makeRegistry(policyEngine: engine)
        let tool = makeTool(defaultPolicy: .deny)
        registry.register(tool: tool, executor: executor)
        engine.addGlobalRule(PolicyRule(
            toolPattern: "test_tool",
            policy: .deny,
            reason: "Blocked by policy"
        ))

        let result = try await registry.executeWithApproval(
            call: makeCall(),
            context: makeContext()
        )

        if case .denied = result.status {
            // Expected
        } else {
            XCTFail("Expected denied status, got \(result.status)")
        }
        XCTAssertFalse(result.success)
        XCTAssertNil(result.toolResult)
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.error!.contains("Blocked by policy"))
    }

    func testRegistryAskExecution() async throws {
        let engine = makeEngine()
        let (registry, executor) = makeRegistry(policyEngine: engine)
        let tool = makeTool(defaultPolicy: .ask)
        registry.register(tool: tool, executor: executor)

        let result = try await registry.executeWithApproval(
            call: makeCall(),
            context: makeContext()
        )

        if case .pendingApproval(let requestID) = result.status {
            XCTAssertGreaterThan(requestID, 0)
        } else {
            XCTFail("Expected pendingApproval status, got \(result.status)")
        }
        XCTAssertFalse(result.success)
        XCTAssertNil(result.toolResult)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.evaluation.decision, .ask)
    }

    func testRegistryCriticalToolAsksEvenWithAlwaysAllow() async throws {
        let engine = makeEngine()
        let (registry, executor) = makeRegistry(policyEngine: engine)
        let tool = makeTool(riskLevel: .critical, defaultPolicy: .ask)
        registry.register(tool: tool, executor: executor)
        engine.addSessionOverride(tool: "test_tool", decision: .alwaysAllow)

        let result = try await registry.executeWithApproval(
            call: makeCall(),
            context: makeContext()
        )

        if case .pendingApproval = result.status {
            // Expected: critical tool always asks
        } else {
            XCTFail("Expected pendingApproval for critical tool, got \(result.status)")
        }
        XCTAssertEqual(result.evaluation.decision, .ask)
    }

    func testRegistryNoPolicyEngineUsesDefault() async throws {
        let (registry, executor) = makeRegistry(policyEngine: nil)
        let tool = makeTool(defaultPolicy: .allow)
        registry.register(tool: tool, executor: executor)

        let result = try await registry.executeWithApproval(
            call: makeCall(),
            context: makeContext()
        )

        XCTAssertEqual(result.status, .allowed)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.evaluation.rule, "tool_default")
    }

    func testRegistryBackwardCompatibleExecute() async throws {
        let engine = makeEngine()
        let (registry, executor) = makeRegistry(policyEngine: engine)
        registry.register(
            tool: makeTool(defaultPolicy: .allow),
            executor: executor
        )

        // Old-style execute still works
        let result = try await registry.execute(call: makeCall(), context: makeContext())

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "ok")
        XCTAssertEqual(result.callID, "call-1")
    }

    func testRegistryBackwardCompatibleExecuteDenied() async throws {
        let engine = makeEngine()
        let (registry, executor) = makeRegistry(policyEngine: engine)
        let tool = makeTool(defaultPolicy: .deny)
        registry.register(tool: tool, executor: executor)

        let result = try await registry.execute(call: makeCall(), context: makeContext())

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
    }

    func testRegistryApprovalRequestIDsIncrement() async throws {
        let engine = makeEngine()
        let (registry, executor) = makeRegistry(policyEngine: engine)
        let tool = makeTool(defaultPolicy: .ask)
        registry.register(tool: tool, executor: executor)

        let result1 = try await registry.executeWithApproval(call: makeCall(id: "c1"), context: makeContext())
        let result2 = try await registry.executeWithApproval(call: makeCall(id: "c2"), context: makeContext())

        if case .pendingApproval(let id1) = result1.status,
           case .pendingApproval(let id2) = result2.status {
            XCTAssertNotEqual(id1, id2)
            XCTAssertEqual(id2, id1 + 1)
        } else {
            XCTFail("Expected two pendingApproval results")
        }
    }

    // MARK: - Session Override Management

    func testRemoveSessionOverride() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .allow)
        engine.addSessionOverride(tool: "test_tool", decision: .alwaysDeny)

        let denied = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())
        XCTAssertEqual(denied.decision, .deny)

        engine.removeSessionOverride(tool: "test_tool")

        let allowed = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())
        XCTAssertEqual(allowed.decision, .allow)
    }

    func testResetClearsEverything() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .allow)

        engine.addSessionOverride(tool: "test_tool", decision: .alwaysDeny)
        engine.addGlobalRule(PolicyRule(toolPattern: "*", policy: .deny, reason: "Block all"))
        engine.addWorkspaceRule(
            PolicyRule(toolPattern: "*", policy: .deny, reason: "Block all"),
            workspace: "/ws"
        )

        engine.reset()

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())
        XCTAssertEqual(result.decision, .allow)
        XCTAssertEqual(result.rule, "tool_default")
    }

    func testClearGlobalRules() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .allow)
        engine.addGlobalRule(PolicyRule(toolPattern: "test_tool", policy: .deny, reason: "Deny"))

        let denied = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())
        XCTAssertEqual(denied.decision, .deny)

        engine.clearGlobalRules()

        let allowed = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())
        XCTAssertEqual(allowed.decision, .allow)
    }

    func testClearWorkspaceRules() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .allow)
        engine.addWorkspaceRule(
            PolicyRule(toolPattern: "test_tool", policy: .deny, reason: "Deny in ws"),
            workspace: "/ws"
        )

        let denied = engine.evaluate(tool: tool, call: makeCall(), context: makeContext(workspace: "/ws"))
        XCTAssertEqual(denied.decision, .deny)

        engine.clearWorkspaceRules(workspace: "/ws")

        let allowed = engine.evaluate(tool: tool, call: makeCall(), context: makeContext(workspace: "/ws"))
        XCTAssertEqual(allowed.decision, .allow)
    }

    // MARK: - Convenience Methods

    func testSetAlwaysAllowSession() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .ask)
        engine.setAlwaysAllow(tool: "test_tool")

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())
        XCTAssertEqual(result.decision, .allow)
        XCTAssertEqual(result.rule, "session_override")
    }

    func testSetAlwaysDenySession() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .allow)
        engine.setAlwaysDeny(tool: "test_tool")

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext())
        XCTAssertEqual(result.decision, .deny)
        XCTAssertEqual(result.rule, "session_override")
    }

    func testSetAlwaysAllowWorkspace() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .deny)
        engine.setAlwaysAllow(tool: "test_tool", workspace: "/ws")

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext(workspace: "/ws"))
        XCTAssertEqual(result.decision, .allow)
        XCTAssertEqual(result.rule, "workspace_rule")
    }

    func testSetAlwaysDenyWorkspace() {
        let engine = makeEngine()
        let tool = makeTool(defaultPolicy: .allow)
        engine.setAlwaysDeny(tool: "test_tool", workspace: "/ws")

        let result = engine.evaluate(tool: tool, call: makeCall(), context: makeContext(workspace: "/ws"))
        XCTAssertEqual(result.decision, .deny)
        XCTAssertEqual(result.rule, "workspace_rule")
    }

    // MARK: - PolicyEvaluationResult Equatable

    func testPolicyEvaluationResultEquatable() {
        let a = PolicyEvaluationResult(decision: .allow, rule: "default", reason: "ok")
        let b = PolicyEvaluationResult(decision: .allow, rule: "default", reason: "ok")
        let c = PolicyEvaluationResult(decision: .deny, rule: "default", reason: "ok")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - ToolApprovalResult Equatable

    func testToolApprovalResultEquatable() {
        let eval = PolicyEvaluationResult(decision: .allow, rule: "default", reason: "ok")
        let result1 = ToolResult(callID: "c1", success: true, output: "out")
        let result2 = ToolResult(callID: "c1", success: true, output: "out")

        let a = ToolApprovalResult(status: .allowed, toolResult: result1, evaluation: eval)
        let b = ToolApprovalResult(status: .allowed, toolResult: result2, evaluation: eval)

        XCTAssertEqual(a, b)
    }
}

// MARK: - Test Helpers

private struct DummyExecutor: ToolExecutor {
    let toolName: String
    let output: String

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        ToolResult(callID: call.id, success: true, output: output)
    }
}
