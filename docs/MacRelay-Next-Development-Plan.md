# MacRelay 下一阶段开发计划

版本：v1.0 日期：2026-07-11

## 当前判断

MacRelay 已完成 Agent Harness 基础骨架：

-   Codex Runtime
-   Claude Code Runtime
-   Event -\> Reducer -\> Snapshot
-   EventStore
-   Replay 基础能力
-   Approval 基础能力
-   自动化测试体系

下一阶段目标：

从「远程控制 Coding Agent」升级为「真正可观察、可恢复、可控制的 Agent
Harness」。

核心闭环：

RuntimeEvent → Trace → Snapshot → Timeline → Approval → Replay

------------------------------------------------------------------------

# Phase 1：RuntimeEvent 标准化（P0）

目标：建立所有 Runtime 共用事件协议。

完成：

-   RuntimeEvent struct
-   RuntimeEventType
-   version 字段
-   Codex / Claude Adapter 统一输出

核心字段：

-   id
-   seq
-   timestamp
-   sessionID
-   runID
-   runtime
-   type
-   payload

------------------------------------------------------------------------

# Phase 2：Trace 持久化（P0）

目标：每次 Agent Run 可完整保存。

目录：

    .macrelay/sessions/{run_id}/
      metadata.json
      trace.jsonl
      snapshot.json
      diff.patch

完成：

-   TraceWriter
-   TraceReader
-   crash-safe 写入
-   trace -\> events -\> snapshot

验收：

删除 snapshot 后，可以通过 trace 重建。

------------------------------------------------------------------------

# Phase 3：Agent Run 模型（P0）

新增核心对象：

Session = 长期上下文

Run = 一次完整任务执行

Run 包含：

-   input
-   trace
-   timeline
-   result
-   files changed
-   duration
-   status

------------------------------------------------------------------------

# Phase 4：Timeline Engine（P0）

不要直接展示日志。

建立：

RuntimeEvent ↓ TimelineBuilder ↓ TimelineItem

类型：

-   UserMessage
-   AgentThinking
-   ToolCall
-   Approval
-   FileChange
-   TestResult
-   Error
-   FinalResult

目标：

用户能回答：

「Agent 到底做了什么？」

------------------------------------------------------------------------

# Phase 5：Approval Policy（P1）

从 accept/reject 升级为权限系统。

增加：

RiskLevel:

-   low
-   medium
-   high
-   critical

Policy:

-   allow
-   ask
-   deny

审批结果进入：

-   Trace
-   Timeline
-   Snapshot

------------------------------------------------------------------------

# Phase 6：测试体系（P1）

补充：

-   Runtime fixture test
-   Trace replay test
-   Timeline build test
-   WebSocket integration test
-   Pairing test
-   GitHub Actions CI

------------------------------------------------------------------------

# 暂缓

## APIAgentRuntime

暂缓原因：

优先理解 Harness。

API Agent 会引入：

-   Agent Loop
-   Context Builder
-   Tool Calling
-   Memory

容易偏离当前目标。

## Tailscale Remote Mode

暂缓原因：

属于产品能力，不是 Harness 核心。

------------------------------------------------------------------------

# 4 周目标

Week 1: RuntimeEvent v1

Week 2: TraceWriter + TraceReader

Week 3: Run Model + Timeline Engine

Week 4: Approval Policy + CI

完成后：

MacRelay = 一个真正的 Agent Harness。
