# MacRelay Agent Harness PRD

> 版本：v1.0  
> 日期：2026-07-02  
> 项目：MacRelay  
> 作者：musk  
> 文档目标：明确 MacRelay 下一阶段从「Mac ↔ iPhone 远程操控 Coding Agent」升级为「通用 Agent Harness」的产品方向、功能范围、技术抽象、里程碑与验收标准。

---

## 1. 背景

MacRelay 当前已经完成初步版本，核心能力是让 iPhone 在局域网内远程操控 Mac 上的 Codex CLI / Claude Code 编程会话。

现有能力包括：

- Mac 与 iPhone 局域网配对通信
- Codex CLI / Claude Code 双引擎支持
- 会话创建、切换、历史管理
- Agent 执行步骤展示
- 消息流式展示
- 文件变更、审批请求、会话状态同步
- `.macrelay/sessions/` 工作区日志
- `.macrelay/memory.md` 空间记忆
- WebSocket + HTTP 协议通信
- token / claim / device credential 配对认证

当前项目已经不只是一个简单的「远程聊天窗口」，而是具备 Agent Harness 雏形：

> MacRelay 可以成为统一管理本地 Coding Agent、API Agent、未来更多 Runtime Provider 的本地 Agent 工作台。

---

## 2. 产品定位

### 2.1 一句话定位

MacRelay 是一个运行在 Mac 本地、可由 iPhone 远程控制的 Agent Harness，用于统一管理 Coding Agent 的运行、权限、工具调用、文件变更、执行轨迹与会话记忆。

### 2.2 不是做什么

MacRelay 不应该只是：

- 一个 iPhone 上的 ChatGPT 聊天壳
- 一个 Codex / Claude Code 的远程遥控器
- 一个单纯把 CLI 输出转发到手机的 WebSocket 工具
- 一个无状态、不可回放、不可审计的消息转发层

### 2.3 应该做什么

MacRelay 应该成为：

- 本地 Agent Runtime 管理器
- iPhone 远程控制台
- Agent 执行过程的 Trace / Replay 系统
- 高风险工具调用审批系统
- 文件变更与 Diff 观察系统
- 多 Runtime Provider 的统一接入层
- 本地 Agent Workspace

---

## 3. 核心问题

当前阶段最大的问题不是「还能不能加更多功能」，而是：

1. Agent 每一次运行能否被完整记录？
2. Agent 每一步行为能否被结构化展示？
3. Agent 的工具调用与文件变更能否被审批？
4. Codex、Claude Code、API Agent 能否走同一套 Runtime 协议？
5. 用户能否在 iPhone 上安全、清晰、低摩擦地控制 Mac 上的 Agent？
6. 项目能否从手动 Probe 验证升级为自动化回归测试？

---

## 4. 产品目标

### 4.1 V1 目标：稳定当前 Harness 主线

将 MacRelay 从「可用原型」推进到「可验证的 Remote Agent Harness」。

核心目标：

- 统一 RuntimeEvent 协议
- 建立 Trace / Replay / Snapshot 三件套
- 把 Probe 沉淀为自动化测试
- 强化审批流
- 建立 Run Timeline UI
- 完善本地安全与设备管理

### 4.2 V2 目标：支持 API Agent Runtime

在不破坏当前 Codex / Claude Code Runtime 的前提下，新增 APIAgentRuntime。

支持 OpenAI / Anthropic / Gemini 等大模型 API，并让它们走同一套：

- Runtime 协议
- Tool Calling
- Approval Gate
- Trace 日志
- File Diff
- Session Journal
- Run Timeline

### 4.3 V3 目标：形成 Agent Spec

引入 `.agent/` 目录，使每个项目可以声明自己的 Agent 配置：

```text
.agent/
  agent.md
  tools.json
  policy.json
  memory.md
```

形成可迁移、可复用、可解释的本地 Agent Workspace。

---

## 5. 用户画像

### 5.1 第一用户：项目作者本人

特征：

- 产品经理 / 产品策划背景
- 有编程和 AI Agent 学习诉求
- 希望通过真实项目理解 Agent Harness
- 关心产品结构、协议、长期可扩展性
- 希望用手机远程观察和控制 Mac 上的 Coding Agent

核心需求：

- 离开 Mac 时也能看 Agent 进展
- 手机上审批危险操作
- 看清楚 Agent 到底做了什么
- 复盘一次 Agent Run 的全过程
- 学习 Pi / Craft 类产品背后的 Harness 思想

### 5.2 第二用户：独立开发者 / AI 编程重度用户

特征：

- 使用 Codex CLI、Claude Code、OpenCode、Aider 等工具
- 经常让 Agent 长时间跑任务
- 关心安全、审批、Diff、回滚
- 不满足于普通 Chat UI

核心需求：

- 多 Agent Runtime 统一管理
- 手机端远程监控
- 文件变更前审批
- Shell 命令前审批
- 失败后快速定位问题
- 运行轨迹可追溯

---

## 6. 核心使用场景

### 6.1 手机远程观察 Agent 执行

用户在 Mac 上启动一个 Codex / Claude Code 任务，离开电脑后，用 iPhone 查看：

- 当前任务状态
- Agent 正在思考什么
- 调用了哪些工具
- 修改了哪些文件
- 是否卡在审批
- 是否执行完成

### 6.2 手机审批危险操作

Agent 准备执行：

- 写文件
- 删除文件
- 运行 Shell 命令
- 安装依赖
- 修改配置
- 访问网络

MacRelay 在 iPhone 上弹出审批卡片：

- 展示操作类型
- 展示命令 / 文件路径 / Diff
- 标记风险等级
- 允许用户选择「允许一次」「拒绝」「总是允许同类操作」

### 6.3 复盘一次 Agent Run

用户打开历史 Session，看到完整 Timeline：

```text
User: 修复登录页面崩溃
Agent: 分析项目结构
Tool: list_files
Tool: read_file LoginView.swift
Tool: edit_file LoginView.swift
Tool: run_tests
Approval: requested
File changed: LoginView.swift
Result: tests passed
Assistant: 已完成修复
```

用户可以看到：

- 每一步时间
- 每个工具调用
- 每次文件变化
- 每次审批
- 最终结果
- 错误信息
- 可回放 trace

### 6.4 切换不同 Runtime

用户可以选择：

- Codex CLI
- Claude Code
- OpenAI API Agent
- Anthropic API Agent
- Gemini API Agent
- 未来其他 CLI / API Runtime

对用户来说，底层 Runtime 不同，但前台体验一致：

- 同样的会话列表
- 同样的 Timeline
- 同样的审批流
- 同样的日志结构
- 同样的 Diff 视图

---

## 7. 产品原则

### 7.1 Harness First

MacRelay 的核心不是聊天，而是 Harness。

聊天只是输入输出的一种形式，真正重要的是：

- 状态
- 事件
- 工具
- 权限
- 文件
- 审批
- 轨迹
- 回放

### 7.2 Runtime Provider 插件化

Codex、Claude Code、API Agent 都只是 Runtime Provider。

MacRelay 不应该把任何一个 Runtime 写死成核心逻辑。

### 7.3 Event 是事实，Snapshot 是结果

事件日志应该记录「发生了什么」。

Snapshot 只是由事件规约出来的当前状态，不应该替代事件本体。

### 7.4 手机端重在控制，不重在编辑

iPhone 不应该承担复杂开发环境的职责。

手机端最重要的是：

- 看状态
- 看变更
- 做审批
- 发轻量指令
- 接管关键决策

### 7.5 安全优先于便利

MacRelay 允许手机远程控制 Mac 上的 Agent，本质上具备高权限。

必须优先保证：

- 设备可信
- 操作可审计
- 权限可控
- 高风险动作可审批
- 配对可撤销

---

## 8. 功能范围

## 8.1 V1：Remote Agent Harness

### 8.1.1 RuntimeEvent 统一协议

#### 需求描述

定义统一 RuntimeEvent，让所有底层 Agent Runtime 输出统一事件。

#### 事件类型

```text
session.started
session.stopped
session.selected
turn.started
assistant.delta
assistant.message.completed
tool.call.requested
tool.call.started
tool.call.completed
tool.call.failed
approval.requested
approval.resolved
file.change.detected
diff.updated
runtime.error
runtime.exited
snapshot.updated
```

#### 验收标准

- Codex Runtime 可以转换为 RuntimeEvent
- Claude Code Runtime 可以转换为 RuntimeEvent
- WebSocket 下发事件只依赖 RuntimeEvent
- iOS UI 不再直接感知 Codex / Claude 原始协议
- 每个事件有稳定 schema

---

### 8.1.2 Trace 日志

#### 需求描述

每次 Agent Run 自动生成 trace 文件，用于复盘、调试、回放。

#### 文件结构

```text
.macrelay/sessions/{session_id}/
  trace.jsonl
  snapshot.json
  metadata.json
  memory.md
  diff.patch
```

#### trace.jsonl 示例

```json
{"seq":1,"type":"session.started","timestamp":"2026-07-02T10:00:00Z","payload":{"runtime":"codex","cwd":"/Users/musk/project"}}
{"seq":2,"type":"turn.started","timestamp":"2026-07-02T10:00:05Z","payload":{"input":"修复登录 bug"}}
{"seq":3,"type":"tool.call.requested","timestamp":"2026-07-02T10:00:08Z","payload":{"tool":"read_file","path":"LoginView.swift"}}
{"seq":4,"type":"file.change.detected","timestamp":"2026-07-02T10:00:20Z","payload":{"path":"LoginView.swift","changeKind":"modified"}}
```

#### 验收标准

- 每个 session 自动生成 trace.jsonl
- 事件按 seq 严格递增
- trace 不依赖 UI 存在
- 异常退出也能保留已产生 trace
- trace 可以用于重建 snapshot

---

### 8.1.3 Snapshot 重建

#### 需求描述

系统可以从 trace 重新构造 session snapshot。

#### 核心逻辑

```text
trace events -> reducer -> snapshot
```

#### 验收标准

- 给定一份 trace.jsonl，可以生成 snapshot.json
- 生成结果与运行时 snapshot 一致
- 支持 fixture 测试
- 支持版本字段，未来 schema 可演进

---

### 8.1.4 Replay 回放

#### 需求描述

iOS 客户端断线重连后，可以通过 replay 拉取缺失事件。

#### 需求细节

- 客户端维护 lastSeenSeq
- 服务端支持 replay(afterSeq)
- 如果事件缓存仍在，返回缺失 events
- 如果缓存不足，返回 needsFullSnapshot
- 客户端自动 fallback 到 snapshot

#### 验收标准

- iPhone 断网后重连不丢状态
- Replay 可以补齐断线期间的事件
- Replay 不重复应用已应用事件
- Snapshot fallback 正常工作

---

### 8.1.5 Run Timeline UI

#### 需求描述

在 Mac / iPhone UI 中新增结构化 Timeline，展示 Agent 执行步骤。

#### Timeline 卡片类型

```text
User Message
Assistant Thinking / Delta
Tool Call
Approval Request
File Change
Diff Update
Error
Final Result
```

#### 展示信息

- 时间
- 类型
- 状态
- Runtime
- 工具名
- 文件路径
- 命令
- Diff 摘要
- 审批状态
- 错误详情

#### 验收标准

- 用户能一眼看出 Agent 当前卡在哪里
- 用户能看到文件变更顺序
- 用户能区分普通消息和工具调用
- 用户能在 Timeline 中处理审批
- Timeline 与 trace 数据结构一致

---

### 8.1.6 Approval Gate

#### 需求描述

建立统一审批机制，所有 Runtime 的高风险操作都必须经过 Approval Gate。

#### 操作风险分级

| 风险等级 | 操作类型 | 默认策略 |
|---|---|---|
| low | read_file / list_files / search_text | allow |
| medium | write_file / edit_file | ask |
| high | run_shell_command / install_dependency | ask |
| critical | delete_file / rm -rf / git push / network credential access | deny or ask |

#### 审批选项

```text
允许一次
拒绝
总是允许此类操作
总是拒绝此类操作
```

#### 审批卡片内容

- Runtime
- Session
- 操作类型
- 工具名称
- 参数
- 文件路径
- 命令内容
- 风险等级
- Diff 预览
- Agent 给出的原因

#### 验收标准

- Codex / Claude Code 的 approval request 能进入统一审批流
- APIAgentRuntime 的 tool call 能进入统一审批流
- iPhone 可以处理审批
- 审批结果回传 Runtime
- 审批结果写入 trace

---

### 8.1.7 Trusted Device 管理

#### 需求描述

用户可以管理已配对的 iPhone 设备。

#### 功能列表

- 查看已配对设备
- 显示设备名称
- 显示最近连接时间
- 显示认证方式
- 删除单个设备
- 重置所有设备
- 重新生成 pairing token
- 查看当前 LAN 暴露状态

#### 验收标准

- 删除设备后，该设备无法继续 challenge-response 登录
- 重置所有设备后，所有旧设备失效
- 配对 token 不明文展示
- deviceSecret 不在无鉴权接口暴露

---

### 8.1.8 Probe 自动化测试

#### 需求描述

将现有 Probe target 沉淀为测试体系。

#### 测试分层

```text
Unit Tests
- RuntimeEvent schema
- Reducer
- Pairing URI
- Challenge signer
- Approval policy

Fixture Tests
- Codex event stream -> RuntimeEvent
- Claude Code event stream -> RuntimeEvent
- RuntimeEvent -> Snapshot

Integration Tests
- 启动 HTTP server
- 启动 WebSocket server
- 模拟 iPhone authorize
- snapshot.get
- session.turn.start
- approval.resolve
```

#### 验收标准

- `swift test` 可覆盖核心协议与 reducer
- fixture 数据稳定
- CI 自动运行
- 关键协议变更会导致测试失败

---

## 8.2 V2：APIAgentRuntime

### 8.2.1 API Runtime 抽象

#### 需求描述

新增 APIAgentRuntime，用于接入 OpenAI / Anthropic / Gemini 等大模型 API。

#### Runtime 架构

```text
AgentRuntime
  ├── CodexRuntime
  ├── ClaudeCodeRuntime
  └── APIAgentRuntime
        ├── OpenAIRuntime
        ├── AnthropicRuntime
        └── GeminiRuntime
```

#### 统一协议

```swift
protocol AgentRuntime {
    func startSession(config: SessionConfig) async throws -> SessionID
    func sendTurn(_ input: UserInput, sessionID: SessionID) async throws
    func stopSession(_ sessionID: SessionID) async throws
    var events: AsyncStream<RuntimeEvent> { get }
}
```

#### 验收标准

- UI 不需要知道底层 Runtime 是 CLI 还是 API
- API Runtime 可以产生相同 RuntimeEvent
- API Runtime 可以使用相同 Tool Registry
- API Runtime 可以进入相同 Approval Gate
- API Runtime 可以写入相同 trace

---

### 8.2.2 Model Provider 管理

#### 需求描述

支持配置不同模型供应商。

#### Provider 类型

```text
OpenAI
Anthropic
Gemini
Custom OpenAI-compatible endpoint
```

#### 配置项

- Provider name
- Base URL
- API Key
- Model
- Max tokens
- Temperature
- Tool calling enabled
- Streaming enabled

#### 安全要求

- API Key 存储在 Keychain
- 不写入 trace
- 不写入日志
- 不通过 WebSocket 下发到 iPhone

#### 验收标准

- 用户可以新增 / 删除 Provider
- 用户可以测试连接
- 用户可以为 session 选择 Provider
- API Key 不明文落盘

---

### 8.2.3 Tool Registry

#### 需求描述

APIAgentRuntime 使用 MacRelay 提供的本地工具能力。

#### V2 首批工具

```text
list_files
read_file
search_text
write_file
run_shell_command
```

#### 工具规范

每个工具需要定义：

- name
- description
- input_schema
- output_schema
- risk_level
- approval_policy
- executor

#### 示例

```json
{
  "name": "write_file",
  "description": "Write content to a file in the current workspace",
  "riskLevel": "medium",
  "approvalPolicy": "ask",
  "inputSchema": {
    "path": "string",
    "content": "string"
  }
}
```

#### 验收标准

- API 模型可以调用工具
- 工具调用前可以进入审批流
- 工具执行结果返回模型
- 工具调用写入 trace
- 工具失败写入 error event

---

### 8.2.4 API Agent Loop

#### 需求描述

实现基础 Agent Loop。

#### 流程

```text
User Input
→ Build Context
→ Model Request
→ Stream Assistant Delta
→ Tool Call Requested
→ Approval Gate
→ Execute Tool
→ Tool Result
→ Continue Model Request
→ Final Answer
```

#### V2 范围限制

不做：

- 多 Agent 协作
- 长期任务调度
- 浏览器自动化
- MCP 市场
- 复杂 Planner
- 多轮自动反思

只做：

- 单 Agent
- 单 Workspace
- 基础 Tool Calling
- 文件修改
- Shell 命令
- Trace
- Approval

#### 验收标准

- 可以完成简单代码修改任务
- 可以读取文件
- 可以写文件
- 可以运行测试命令
- 手机端可以审批工具调用
- 完成后生成完整 Timeline

---

## 8.3 V3：Agent Spec

### 8.3.1 `.agent/agent.md`

#### 需求描述

定义项目级 Agent 行为说明。

#### 示例

```md
# Swift Coding Agent

你是一个 Swift 项目开发助手。

目标：
- 理解现有项目结构
- 小步修改
- 每次修改后运行测试
- 不要未经确认删除文件

代码风格：
- 优先保持现有架构
- 不做不必要的大重构
- 解释关键设计取舍
```

---

### 8.3.2 `.agent/tools.json`

#### 需求描述

定义当前项目允许使用的工具。

#### 示例

```json
{
  "tools": [
    "list_files",
    "read_file",
    "search_text",
    "write_file",
    "run_shell_command"
  ]
}
```

---

### 8.3.3 `.agent/policy.json`

#### 需求描述

定义当前项目的权限策略。

#### 示例

```json
{
  "approvalPolicy": {
    "read_file": "allow",
    "list_files": "allow",
    "search_text": "allow",
    "write_file": "ask",
    "run_shell_command": "ask",
    "delete_file": "deny"
  }
}
```

---

### 8.3.4 `.agent/memory.md`

#### 需求描述

项目长期记忆。

内容包括：

- 项目目标
- 架构说明
- 技术栈
- 已知坑
- 重要决策
- 用户偏好
- 常用命令

---

## 9. 信息架构

### 9.1 Mac 端

```text
MacRelay
  Sidebar
    - New Session
    - Runtime Selector
    - Session List
    - Workspace Selector
    - Device Status
    - Settings

  Main Workspace
    - Chat
    - Run Timeline
    - File Diff
    - Approval Panel

  Inspector
    - Runtime Info
    - Model Settings
    - Session Metadata
    - Trace
    - Memory
```

### 9.2 iPhone 端

```text
Home
  - Connection Status
  - Active Session
  - Session List

Session Detail
  - Timeline
  - Chat Input
  - Approval Cards
  - File Changes
  - Final Result

Settings
  - Pairing
  - Trusted Devices
  - Runtime Providers
  - Approval Policy
```

---

## 10. 关键用户流程

### 10.1 配对流程

```text
Mac 启动 MacRelay
→ 生成 pairing URI / QR Code
→ iPhone 扫码
→ iPhone 调用 /pairing/claim
→ 获取 deviceID + deviceSecret
→ 存入 iPhone Keychain
→ WebSocket challenge-response 登录
→ 配对成功
```

### 10.2 远程执行流程

```text
iPhone 输入任务
→ WebSocket session.turn.start
→ MacRelay 转发给 Runtime
→ Runtime 产生 RuntimeEvent
→ MacRelay 记录 trace
→ MacRelay 广播事件
→ iPhone Timeline 更新
```

### 10.3 审批流程

```text
Runtime 请求工具调用
→ MacRelay 判断风险等级
→ 生成 approval.requested
→ iPhone 展示审批卡
→ 用户选择 allow / reject
→ approval.resolved 回传
→ Runtime 继续或终止
→ trace 记录审批结果
```

### 10.4 Replay 流程

```text
iPhone 断线
→ MacRelay 继续运行 Agent
→ iPhone 重连
→ 发送 replay.from afterSeq
→ 服务端返回缺失 events
→ iPhone 补齐 Timeline
→ 如果缓存不足，拉 snapshot
```

---

## 11. 数据模型

### 11.1 RuntimeEvent

```json
{
  "id": "uuid",
  "seq": 123,
  "type": "tool.call.requested",
  "version": 1,
  "timestamp": "2026-07-02T10:00:00Z",
  "sessionID": "session_uuid",
  "turnID": "turn_uuid",
  "runtime": "codex",
  "correlationID": "uuid",
  "payload": {}
}
```

### 11.2 Session Metadata

```json
{
  "sessionID": "uuid",
  "runtime": "codex",
  "workspace": "/Users/musk/project",
  "createdAt": "2026-07-02T10:00:00Z",
  "updatedAt": "2026-07-02T10:10:00Z",
  "status": "running",
  "title": "修复登录 bug",
  "lastSeq": 42
}
```

### 11.3 Approval Request

```json
{
  "approvalID": "uuid",
  "sessionID": "uuid",
  "turnID": "uuid",
  "toolName": "run_shell_command",
  "riskLevel": "high",
  "reason": "Agent wants to run tests",
  "payload": {
    "command": "swift test"
  },
  "status": "pending"
}
```

### 11.4 File Change

```json
{
  "path": "Sources/App/LoginView.swift",
  "changeKind": "modified",
  "diffSummary": "+12 -4",
  "diff": "...",
  "source": "tool.write_file"
}
```

---

## 12. 协议设计

### 12.1 WebSocket Envelope

```json
{
  "id": "uuid",
  "type": "session.turn.start",
  "version": 1,
  "seq": 123,
  "correlationID": "uuid",
  "timestamp": "2026-07-02T10:00:00Z",
  "payload": {}
}
```

### 12.2 Client Commands

```text
snapshot.get
replay.from
heartbeat.ping
session.list
session.start
session.stop
session.select
session.turn.start
session.settings.update
approval.resolve
runtime.list
runtime.select
provider.list
provider.test
```

### 12.3 Server Events

```text
session.snapshot
session.started
session.status.changed
turn.started
assistant.delta
tool.call.requested
tool.call.completed
approval.requested
approval.resolved
file.change.detected
diff.updated
runtime.error
heartbeat.pong
```

---

## 13. 安全设计

### 13.1 认证

支持两种方式：

1. Pairing token
2. Device challenge-response

推荐长期使用 challenge-response。

### 13.2 Secret 存储

Mac：

- deviceSecret 存储在 Keychain
- API Key 存储在 Keychain
- pairing token 短期有效

iPhone：

- deviceSecret 存储在 Keychain
- 不持久化 API Key
- 不保存 Mac 本地敏感路径外的信息

### 13.3 LAN 暴露

Mac 端需要清晰展示：

- 当前监听地址
- HTTP port
- WebSocket port
- 是否监听 localhost
- 是否监听 LAN IP
- 当前连接设备数量

### 13.4 操作权限

所有高风险操作必须经过 policy 判断：

```text
allow
ask
deny
```

策略来源优先级：

```text
Session override
> Workspace .agent/policy.json
> Global Settings
> Default Policy
```

---

## 14. 非功能需求

### 14.1 性能

- assistant.delta 展示延迟 < 300ms
- WebSocket reconnect 后 2s 内恢复状态
- trace 写入不能阻塞主 UI
- 单 session 支持至少 10,000 条事件

### 14.2 稳定性

- Runtime 崩溃不导致 MacRelay 崩溃
- iPhone 断线不影响 Mac Runtime 继续执行
- trace 写入失败要有 error event
- WebSocket 客户端异常断开要自动清理连接状态

### 14.3 可维护性

- Codex / Claude / API Runtime 不能互相耦合
- UI 不直接依赖 Runtime 原始协议
- 事件 schema 需要版本号
- Probe 与 Test 数据要可复用

### 14.4 可观测性

- 每个 session 有 metadata
- 每个 event 有 seq
- 每个 command 有 correlationID
- 每个 error 有 code + message
- 支持导出 trace

---

## 15. 里程碑

## Milestone 1：RuntimeEvent & Trace

目标：完成事件统一和 trace 落盘。

范围：

- 定义 RuntimeEvent schema
- Codex / Claude event 转 RuntimeEvent
- trace.jsonl 写入
- metadata.json 写入
- snapshot.json 生成
- 基础 fixture test

验收：

- 跑一次 Codex session 能生成完整 trace
- trace 能重建 snapshot
- iOS 仍能正常显示消息与状态

---

## Milestone 2：Replay & Timeline

目标：完成断线重连和结构化 Timeline。

范围：

- replay.from 完善
- needsFullSnapshot fallback
- Timeline 数据模型
- iOS Timeline UI
- Mac Timeline UI
- File Change 卡片
- Error 卡片

验收：

- iPhone 断线后重连不丢事件
- 用户能看到完整执行步骤
- Timeline 与 trace 数据一致

---

## Milestone 3：Approval Gate

目标：统一审批流。

范围：

- ApprovalPolicy
- RiskLevel
- approval.requested event
- approval.resolve command
- iPhone 审批卡片
- trusted device 管理基础能力

验收：

- Shell 命令前触发审批
- 文件写入前可触发审批
- 审批结果可回传 Runtime
- 审批记录写入 trace

---

## Milestone 4：Probe to Tests

目标：把手动 Probe 升级为自动化回归。

范围：

- Reducer unit tests
- Protocol encode/decode tests
- Pairing tests
- Challenge signer tests
- Runtime fixture tests
- WebSocket integration tests
- GitHub Actions CI

验收：

- `swift test` 可跑核心测试
- CI 自动执行
- 协议破坏会失败

---

## Milestone 5：APIAgentRuntime MVP

目标：支持第一个 API Agent Runtime。

范围：

- OpenAI Provider
- API Key Keychain 存储
- Model config
- Streaming response
- Tool Registry
- read_file / list_files / search_text / write_file / run_shell_command
- Approval Gate 接入
- Trace 接入

验收：

- 用户可以用 API Agent 完成一次简单代码修改
- 工具调用出现在 Timeline
- 文件变更出现在 Diff
- Shell 命令需要审批
- trace 完整记录全过程

---

## Milestone 6：Agent Spec

目标：建立项目级 Agent 配置。

范围：

- `.agent/agent.md`
- `.agent/tools.json`
- `.agent/policy.json`
- `.agent/memory.md`
- Workspace 加载逻辑
- UI 展示当前 Agent Spec

验收：

- 不同项目可以使用不同 policy
- APIAgentRuntime 可以读取 agent.md
- 工具权限受 policy 控制
- memory.md 可以进入上下文构建

---

## 16. 成功指标

### 16.1 产品指标

- 用户可以在 iPhone 上完成一次完整远程 Agent 控制
- 用户可以复盘任意一次历史 Run
- 用户可以清楚知道 Agent 改了什么文件
- 用户可以阻止高风险操作
- 用户可以切换 Codex / Claude / API Runtime

### 16.2 技术指标

- RuntimeEvent 覆盖 90% 以上核心事件
- trace 可以 100% 重建 snapshot
- 核心 reducer 有自动化测试
- WebSocket 断线重连稳定
- Approval 关键路径有 integration test

### 16.3 学习指标

这个项目的学习价值不在于「又做了一个 Agent」，而在于真正理解：

- Agent Runtime
- Tool Calling
- Approval Gate
- Trace / Replay
- State Reducer
- Runtime Provider
- Local Workspace
- Secure Remote Control

---

## 17. 风险与应对

### 17.1 功能膨胀

风险：

API Runtime、MCP、多 Agent、插件市场都很诱人，容易做散。

应对：

V1 只做 Harness 基础设施，不做 API Runtime。  
V2 再做 APIAgentRuntime MVP。  
V3 再做 Agent Spec。

---

### 17.2 安全风险

风险：

手机远程控制 Mac 上的 Agent，一旦认证或权限设计薄弱，风险很高。

应对：

- device challenge-response
- Keychain 存储
- trusted device 管理
- Approval Gate
- risk policy
- LAN 状态提示

---

### 17.3 Runtime 差异过大

风险：

Codex、Claude Code、OpenAI API 的事件结构不同，统一抽象可能变复杂。

应对：

先定义最小 RuntimeEvent 子集：

```text
session
turn
assistant delta
tool call
approval
file change
error
```

高级能力作为 optional capabilities。

---

### 17.4 Replay 复杂度

风险：

事件回放、snapshot 重建、断线同步可能出现状态错乱。

应对：

- seq 单调递增
- reducer 纯函数化
- fixture test
- snapshot fallback
- event schema version

---

## 18. 当前最应该做的 5 件事

### 1. 定义 RuntimeEvent v1

这是地基。

没有统一事件，后面的 Timeline、Trace、API Runtime 都会混乱。

### 2. 改造 trace 记录方式

不要只记录 snapshot payload。

要记录「真实发生的事件」，snapshot 应该由事件推导。

### 3. 把 SessionStateReducer 做成可回放核心

Reducer 要成为系统心脏：

```text
RuntimeEvent -> SessionSnapshot
```

### 4. 做 Run Timeline

UI 不要继续只像聊天窗口。

必须展示 Agent 行为结构。

### 5. 把 Probe 变成 Tests

否则项目会停留在「本机试过」阶段。

---

## 19. 建议的开发顺序

```text
第 1 周：
- RuntimeEvent schema
- TraceWriter
- TraceReader
- RuntimeEvent -> Snapshot reducer

第 2 周：
- Codex / Claude adapter 改造
- fixture tests
- snapshot rebuild

第 3 周：
- Replay 完善
- iOS Timeline 初版
- Mac Timeline 初版

第 4 周：
- Approval Gate
- Risk Policy
- Trusted Device 管理初版

第 5 周：
- Probe 迁移到 Tests
- GitHub Actions CI

第 6 周：
- OpenAI APIAgentRuntime MVP
- Tool Registry
- API Agent Loop
```

---

## 20. 结论

MacRelay 下一阶段不应该急着变成 Pi / Craft 的复制品。

更好的路线是：

> 先把 MacRelay 做成稳定、可验证、安全的 Agent Harness；再把 Codex、Claude Code、API Agent 都作为 Runtime Provider 接进来。

真正的壁垒不是「接了几个模型」，而是：

- 统一 Runtime 抽象
- 完整 Trace / Replay
- 清晰 Timeline
- 安全 Approval Gate
- 本地 Workspace
- 手机远程控制体验

这条路更难，但更有价值。

MacRelay 最终应该成为：

> 一个运行在 Mac 本地、可由 iPhone 安全控制、支持多 Runtime Provider、可记录可回放可审批的 Agent Harness。

这比「又一个 AI 编程聊天窗口」强得多。
