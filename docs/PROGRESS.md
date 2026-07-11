# MacRelay 项目进度

最后更新：2026-07-11

## 总体进度

| 里程碑 | 状态 | 完成度 |
|--------|------|--------|
| M1: RuntimeEvent & Trace | 进行中 | 60% |
| M2: Replay & Run Timeline | 进行中 | 50% |
| M3: Approval Gate | 进行中 | 40% |
| M4: Probe to Tests | 进行中 | 55% |
| M5: Tailscale Remote Mode | 未开始 | 0% |
| M6: APIAgentRuntime MVP | 未开始 | 0% |
| M7: Agent Spec | 未开始 | 0% |

**V1 整体完成度：~50%**

---

## M1: RuntimeEvent & Trace（60%）

### 已完成 ✅

- `CodexAppServerEvent` 事件类型定义（response/notification/serverRequest）
- `SessionReducerAction` 统一 action 枚举（threadStarted/turnStarted/assistantDelta/toolCall/approval/fileChange/error 等）
- `SessionStateReducer` 纯函数 reducer：`CodexAppServerEvent → [SessionReducerAction] → SessionSnapshot`
- `MacRelayService.ingest()` 事件摄入 → reducer → snapshot 更新
- `EventStore` 事件存储（容量限制，seq 递增）
- `StoredRelayEvent` 事件包装（带 seq 和时间戳）
- Codex Runtime 事件 → RuntimeEvent 转换
- Claude Code Runtime 事件 → RuntimeEvent 转换
- 24 个 reducer 单元测试

### 未完成 ❌

- **trace.jsonl 落盘**：当前事件只存在内存中的 `EventStore`，没有持久化到 `.macrelay/sessions/{id}/trace.jsonl`
- **metadata.json**：session 元数据没有独立落盘
- **统一 RuntimeEvent schema**：当前 Codex 和 Claude Code 的事件通过 `normalizedEvent()` 转换，但没有一个独立的 `RuntimeEvent` struct/schema
- **事件版本号**：schema 没有 version 字段

### 下一步建议

1. 定义 `RuntimeEvent` struct（带 seq/type/timestamp/sessionID/payload/version）
2. 实现 `TraceWriter`：将 `StoredRelayEvent` 写入 `trace.jsonl`
3. 实现 `TraceReader`：从 `trace.jsonl` 重建 snapshot
4. 添加 fixture test：固定事件流 → 预期 snapshot

---

## M2: Replay & Run Timeline（50%）

### 已完成 ✅

- `EventStore.replay(afterSeq:maxEvents:)` 事件回放
- iOS `refreshSnapshot(includeReplay:)` 断线重连后拉取缺失事件
- `relayService.replay()` 返回 `EventReplayResult`
- `turn/started` / `turn/completed` / `assistant.delta` 事件流式展示
- `TurnStep` 步骤跟踪（toolCall/approval/thinking/error/fileChange）
- iOS 端步骤列表展示（`AssistantTextParser.extractNewSteps`）

### 未完成 ❌

- **结构化 Run Timeline UI**：当前只是步骤列表，不是 PRD 要求的 Timeline 卡片视图
- **Timeline 卡片类型**：缺少 Tool Call Requested/Running/Completed/Failed、Approval Request/Resolved、File Change、Error、Final Result 等独立卡片
- **needsFullSnapshot fallback**：replay 失败时的自动 fallback 逻辑不完善
- **Mac 端 Timeline UI**：Mac 端没有独立的 Timeline 视图
- **文件变更顺序展示**：fileChanges 只是路径列表，没有按时间排序的变更流

### 下一步建议

1. 定义 `TimelineItem` 数据模型（对应 PRD 中的卡片类型）
2. 从 `EventStore` 的事件流构建 Timeline
3. iOS 端实现 Timeline 卡片视图（可折叠参数、展开 Diff、高亮审批）
4. Mac 端同步 Timeline 视图

---

## M3: Approval Gate（40%）

### 已完成 ✅

- `approval.requested` 事件处理
- `approval.resolve` 命令（accept/reject）
- iOS 端审批卡片基础 UI
- Mac 端审批面板
- 审批结果回传 Runtime
- `pendingApprovals` 在 snapshot 中同步

### 未完成 ❌

- **风险分级**：没有 low/medium/high/critical 分级
- **审批策略**：没有 `ApprovalPolicy`（allow/ask/deny）按工具类型配置
- **审批卡片内容**：缺少风险等级标识、Diff 预览、Agent 原因说明
- **审批选项**：只有 accept/reject，缺少「总是允许此类操作」
- **审批记录写入 trace**：审批结果没有写入事件日志
- **`.agent/policy.json`**：没有项目级策略配置

### 下一步建议

1. 定义 `RiskLevel` 枚举和 `ApprovalPolicy` 按工具映射
2. 在审批卡片中展示风险等级和操作详情
3. 审批结果写入事件日志
4. 支持「总是允许」策略

---

## M4: Probe to Tests（55%）

### 已完成 ✅

- `SessionStateReducer` 24 个单元测试
- `ClaudeCodeSessionStartRaceConditionTests` 8 个回归测试
- `EmptySessionSnapshotTests` 6 个回归测试
- `SessionMessageCacheTests` 5 个测试
- `MacRelayRuntimeCommandDispatcherTests` 4 个测试
- `WorkspaceSessionGrouperTests` 3 个测试
- `ClaudeCodeSettingsReaderTests` 5 个测试
- `RateLimitSnapshotFormatTests` 3 个测试
- 协议 encode/decode 测试
- **总计 78 个测试，全部通过**

### 未完成 ❌

- **GitHub Actions CI**：没有自动化 CI 流水线
- **Challenge signer 测试**：challenge-response 认证没有测试
- **WebSocket 集成测试**：没有端到端 WebSocket 测试
- **Runtime fixture 测试**：没有固定 Codex/Claude 事件流 → 预期 output 的测试
- **Pairing 流程测试**：HTTP 配对没有自动化测试

### 下一步建议

1. 添加 GitHub Actions CI（swift test on push）
2. 添加 challenge-response 测试
3. 添加 WebSocket 集成测试框架
4. 添加 Codex/Claude 事件流 fixture 测试

---

## M5: Tailscale Remote Mode（0%）

未开始。

### 待实现

- Remote Access 设置页
- Tailscale IP / MagicDNS 检测
- iPhone 添加远程 Mac
- Tailscale endpoint 存储
- 远程连接状态展示
- challenge-response 认证复用

---

## M6: APIAgentRuntime MVP（0%）

未开始。

### 待实现

- OpenAI Provider
- OpenAI-compatible Provider
- API Key Keychain 存储
- Tool Registry（read_file/list_files/search_text/write_file/run_shell_command）
- API Agent Loop
- Approval Gate 接入
- Trace 接入

---

## M7: Agent Spec（0%）

未开始。

### 待实现

- `.agent/agent.md`
- `.agent/tools.json`
- `.agent/policy.json`
- `.agent/memory.md`
- Workspace 加载逻辑

---

## 技术债务

| 项目 | 优先级 | 说明 |
|------|--------|------|
| trace.jsonl 落盘 | 高 | 事件只在内存中，重启丢失 |
| 统一 RuntimeEvent schema | 高 | 当前 Codex/Claude 事件结构不统一 |
| 结构化 Timeline UI | 中 | 当前只是步骤列表 |
| 风险分级审批 | 中 | 当前只有 accept/reject |
| GitHub Actions CI | 中 | 没有自动化测试流水线 |
| WebSocket 集成测试 | 低 | 端到端测试缺失 |

---

## 建议的下一步（2 周）

**第 1 周：Trace 落盘 + 统一事件**
1. 定义 `RuntimeEvent` struct
2. 实现 `TraceWriter`（trace.jsonl 写入）
3. 实现 `TraceReader`（从 trace 重建 snapshot）
4. 添加 fixture test

**第 2 周：Timeline 数据模型 + CI**
1. 定义 `TimelineItem` 数据模型
2. 从事件流构建 Timeline
3. 添加 GitHub Actions CI
4. 添加 challenge-response 测试
