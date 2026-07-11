# MacRelay Agent Harness PRD v1.2 更新

日期：2026-07-11

## 战略调整

MacRelay 下一阶段重点：

从：

远程控制 Codex / Claude Code

调整为：

构建可观察、可恢复、可控制的 Agent Harness。

------------------------------------------------------------------------

# 新增核心概念：Agent Run

Session 管长期上下文。

Run 管一次完整任务执行。

示例：

Session: Swift 项目开发

Run: - 修复登录 Bug - 增加支付功能 - 优化性能

每个 Run：

-   input
-   trace
-   timeline
-   result
-   files changed
-   duration
-   status

------------------------------------------------------------------------

# 核心架构

    Runtime
      ↓
    RuntimeEvent
      ↓
    Trace
      ↓
    Reducer
      ↓
    Snapshot
      ↓
    Timeline
      ↓
    Approval
      ↓
    Replay

------------------------------------------------------------------------

# M1 RuntimeEvent & Trace

目标：

让 Agent Run 完全可追踪。

新增 RuntimeEvent：

-   id
-   seq
-   version
-   timestamp
-   sessionID
-   runID
-   runtime
-   type
-   payload

------------------------------------------------------------------------

# M2 Timeline

Timeline 不再是日志列表。

升级为：

Agent 行为审计视图。

用户需要知道：

-   Agent 做了什么
-   使用什么工具
-   修改什么文件
-   审批什么
-   哪里失败

TimelineItem：

-   UserMessage
-   AgentThinking
-   ToolCall
-   Approval
-   FileChange
-   TestResult
-   Error
-   FinalResult

------------------------------------------------------------------------

# M3 Approval Gate

从：

accept/reject

升级：

Policy Engine

RiskLevel：

-   low
-   medium
-   high
-   critical

Policy：

-   allow
-   ask
-   deny

审批结果必须进入：

-   Trace
-   Timeline
-   Snapshot

------------------------------------------------------------------------

# M4 Probe to Tests

目标：

从手动验证升级为持续保障。

新增：

-   Runtime fixture test
-   Trace replay test
-   Timeline test
-   WebSocket integration test

------------------------------------------------------------------------

# M5 Remote Access

保持：

-   Tailscale Remote Mode
-   Cloudflare Tunnel
-   Cloud Relay

但优先级下降。

------------------------------------------------------------------------

# M6 APIAgentRuntime

保持：

支持：

-   OpenAI
-   Anthropic
-   Gemini
-   DeepSeek
-   MIMO
-   OpenAI-compatible Provider

进入条件：

必须先完成：

-   RuntimeEvent
-   Trace
-   Timeline
-   Approval

------------------------------------------------------------------------

# 最终定位

MacRelay 不应该成为：

AI 聊天客户端。

而应该成为：

运行在本地、支持多 Runtime、具备 Trace / Replay / Approval 能力的 Agent
Harness。

核心价值：

让 Agent 变得：

-   可理解
-   可控制
-   可恢复
