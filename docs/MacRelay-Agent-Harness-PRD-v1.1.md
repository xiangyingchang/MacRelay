# MacRelay Agent Harness PRD

> 版本：v1.1  
> 日期：2026-07-02  
> 项目：MacRelay  
> 作者：musk  
> 文档目标：明确 MacRelay 下一阶段从「Mac ↔ iPhone 远程操控 Coding Agent」升级为「通用 Agent Harness」的产品方向、功能范围、技术抽象、远程访问方案、里程碑与验收标准。

---

## 0. 核心概念解释

本章节用于解释 PRD 中反复出现的几个核心词，避免概念堆叠。

### 0.1 Harness 是什么？

Harness 可以理解成 **Agent 的运行时控制系统**。

它不是模型本身，也不是聊天窗口，而是包在 Agent 外面的一整套运行环境：

```text
模型 / Runtime
工具调用
权限审批
事件记录
状态管理
文件变更
错误处理
断线恢复
历史回放
UI 可观测性
```

一个好的 Agent Harness 要回答：

```text
Agent 做了什么？
为什么做？
调用了什么工具？
改了什么文件？
谁批准了什么？
哪里失败了？
能不能回放？
能不能恢复？
能不能复盘？
```

MacRelay 的长期目标就是成为一个本地 Agent Harness。

---

### 0.2 Trace 是什么？

Trace = **Agent 的完整运行轨迹**。

它记录一次 Agent Run 从开始到结束发生的每一件事：

```text
用户发起了什么任务
Agent 输出了什么内容
Agent 调用了什么工具
工具输入是什么
工具输出是什么
请求了什么审批
用户是否批准
改了哪些文件
运行了什么命令
哪里失败了
最终结果是什么
```

可以把 Trace 理解成：

> Agent 的行车记录仪。

示例：

```json
{"seq":1,"type":"turn.started","payload":{"input":"修复登录 bug"}}
{"seq":2,"type":"tool.call.requested","payload":{"tool":"read_file","path":"LoginView.swift"}}
{"seq":3,"type":"tool.call.completed","payload":{"tool":"read_file","ok":true}}
{"seq":4,"type":"approval.requested","payload":{"tool":"write_file","path":"LoginView.swift"}}
{"seq":5,"type":"approval.resolved","payload":{"decision":"allow_once"}}
{"seq":6,"type":"file.change.detected","payload":{"path":"LoginView.swift","+":12,"-":4}}
{"seq":7,"type":"turn.completed","payload":{"status":"success"}}
```

Trace 的价值：

```text
复盘：知道 Agent 到底干了什么
Debug：失败时知道死在哪一步
Replay：断线后补齐事件
测试：用固定 trace 验证 reducer
审计：知道谁批准了什么操作
学习：理解 Agent Harness 的真实运行过程
```

没有 Trace，Harness 就是瞎跑；有 Trace，Harness 才可理解、可调试、可信任。

---

### 0.3 Replay 是什么？

Replay = **事件回放 / 断线补放**。

比如 iPhone 断网了 30 秒，但 Mac 上的 Agent 仍然在继续执行。iPhone 重新连接后，可以告诉 MacRelay：

```text
我上次看到 seq=120，现在请从 seq=121 开始把漏掉的事件补给我。
```

MacRelay 返回缺失事件，iPhone 继续更新 Timeline。

Replay 解决的是：

```text
断线重连后不丢状态
历史 session 可以回放
UI 可以根据事件重新构建
测试可以用固定事件流验证系统
```

---

### 0.4 Snapshot 是什么？

Snapshot = **当前状态快照**。

它不是完整历史，而是某一刻的系统状态。

例如：

```json
{
  "status": "waitingOnApproval",
  "activeTurn": "正在修复登录 bug",
  "pendingApprovals": ["run_shell_command swift test"],
  "fileChanges": ["LoginView.swift"],
  "lastEventSeq": 128
}
```

Trace 像完整电影，Snapshot 像暂停时的一张截图。

Snapshot 的作用：

```text
iPhone 第一次连接时快速拿到当前状态
断线太久、Replay 补不回来时直接恢复画面
App 重启后恢复上次会话
UI 根据当前状态快速渲染
```

三者关系：

```text
Trace = 全部历史
Replay = 从某个点补历史
Snapshot = 当前状态
```

更准确地说：

```text
RuntimeEvent -> Trace -> Reducer -> Snapshot -> Timeline
```

---

### 0.5 Probe 是什么？

Probe = **探针 / 小型验证程序**。

它不是正式产品功能，而是开发时用来验证某条链路是否能跑通的小程序。

示例：

```text
PairingURIProbe
验证配对 URI 能不能生成和解析

MacRelayWebSocketServerProbe
验证 WebSocket server 能不能启动、认证、收发消息

ChallengeSignerProbe
验证 challenge-response 签名是否正确

TurnEventTraceProbe
验证 turn 事件能不能被记录成 trace
```

Probe 的价值是快速验证模块，不用每次都启动完整 App。

但 Probe 如果一直手动跑，就会变成：

```text
我记得它以前能跑。
```

下一步要把 Probe 沉淀成自动化测试：

```text
Probe -> Fixture Test / Integration Test
```

也就是每次改代码后，由测试自动确认这些链路没有被改坏。

---

### 0.6 Challenge-Response 是什么？

Challenge-Response = **挑战-响应认证**。

它解决的问题是：

> 手机连接 Mac 时，不要每次都把长期密钥 deviceSecret 直接发过去。

如果每次都发 deviceSecret，一旦网络包被抓到，别人可能复用这个 secret 冒充你的手机。

Challenge-Response 的思路是：

```text
Mac：你说你是已配对设备？证明给我看。
iPhone：可以，你给我一道临时题。
Mac：题目是 nonce = abc123。
iPhone：我用 deviceSecret 算出答案 = HMAC(nonce, deviceSecret)。
Mac：我也用本地保存的 deviceSecret 算一遍，答案一致，说明你真有 secret。
```

关键点：

```text
deviceSecret 从头到尾不在网络上传输。
```

首次配对：

```text
1. Mac 生成 deviceID + deviceSecret
2. iPhone 通过安全 claim 流程拿到 deviceSecret
3. Mac 本地保存 deviceSecret
4. iPhone Keychain 保存 deviceSecret
```

后续连接：

```text
1. iPhone 发 deviceID 给 Mac
2. Mac 生成一次性 nonce
3. Mac 把 nonce 发给 iPhone
4. iPhone 用 deviceSecret 对 nonce 做 HMAC-SHA256
5. iPhone 把签名结果发给 Mac
6. Mac 用本地 deviceSecret 也算一遍
7. 两边结果一致 -> 认证成功
8. nonce 作废，不能重复使用
```

安全要求：

```text
长期设备认证必须使用 challenge-response
deviceSecret 只在首次配对 claim 时下发一次
后续 WebSocket 连接不得发送 deviceSecret 明文
每个 nonce 只能使用一次
nonce 必须有过期时间
认证失败必须关闭连接
用户删除 trusted device 后，旧 deviceSecret 立即失效
```

这块很重要，因为 MacRelay 不是普通聊天工具，而是远程控制 Mac 上的 Agent。

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
- Agent 行为审计视图

---

## 3. 核心问题

当前阶段最大的问题不是「还能不能加更多功能」，而是：

1. Agent 每一次运行能否被完整记录？
2. Agent 每一步行为能否被结构化展示？
3. 用户能不能非常清楚地知道 Agent 做了什么、通过了什么、审批了什么？
4. Agent 的工具调用与文件变更能否被审批？
5. Codex、Claude Code、API Agent 能否走同一套 Runtime 协议？
6. 用户能否在 iPhone 上安全、清晰、低摩擦地控制 Mac 上的 Agent？
7. 项目能否从手动 Probe 验证升级为自动化回归测试？
8. 局域网之外，能否安全远程连接家里的 Mac？

---

## 4. 产品目标

### 4.1 V1 目标：稳定当前 Harness 主线

将 MacRelay 从「可用原型」推进到「可验证的 Remote Agent Harness」。

核心目标：

- 统一 RuntimeEvent 协议
- 建立 Trace / Replay / Snapshot 三件套
- 把 Probe 沉淀为自动化测试
- 强化审批流
- 建立 Run Timeline / Agent 行为审计视图
- 完善本地安全与设备管理

### 4.2 V1.5 目标：远程访问模式

在局域网连接之外，支持更方便但安全的远程控制方式。

优先支持：

```text
Tailscale Remote Mode
```

后续支持：

```text
Cloudflare Tunnel Mode
Cloud Relay Mode
```

### 4.3 V2 目标：支持 API Agent Runtime

在不破坏当前 Codex / Claude Code Runtime 的前提下，新增 APIAgentRuntime。

支持：

```text
OpenAI
Anthropic
Gemini
DeepSeek
MIMO
Mistral
Moonshot / Kimi
Qwen / 通义千问
Doubao / 豆包
OpenAI-compatible endpoint
Local model endpoint，例如 Ollama / LM Studio
```

并让它们走同一套：

- Runtime 协议
- Tool Calling
- Approval Gate
- Trace 日志
- File Diff
- Session Journal
- Run Timeline

### 4.4 V3 目标：形成 Agent Spec

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
- 希望电脑在家时，人在外面也可以安全连接

核心需求：

- 离开 Mac 时也能看 Agent 进展
- 手机上审批危险操作
- 看清楚 Agent 到底做了什么
- 知道 Agent 通过了什么、卡在什么、等我批什么
- 复盘一次 Agent Run 的全过程
- 学习 Pi / Craft 类产品背后的 Harness 思想
- 支持局域网以外的远程访问

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
- 安全远程连接家中或办公室的开发机

---

## 6. 核心使用场景

### 6.1 手机远程观察 Agent 执行

用户在 Mac 上启动一个 Codex / Claude Code 任务，离开电脑后，用 iPhone 查看：

- 当前任务状态
- Agent 正在做什么
- Agent 已经通过了哪些步骤
- Agent 调用了哪些工具
- Agent 修改了哪些文件
- 是否卡在审批
- 是否执行完成
- 是否有错误
- 下一步会做什么

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
- 解释 Agent 为什么要这么做
- 允许用户选择「允许一次」「拒绝」「总是允许同类操作」

### 6.3 复盘一次 Agent Run

用户打开历史 Session，看到完整 Timeline：

```text
User: 修复登录页面崩溃
Agent: 分析任务
Tool: list_files
Tool: read_file LoginView.swift
Tool: search_text "LoginState"
Approval: requested write_file LoginView.swift
User: allow_once
File changed: LoginView.swift +12 -4
Approval: requested run_shell_command swift test
User: allow_once
Tool: run_shell_command swift test
Result: tests passed
Assistant: 已完成修复
```

用户可以看到：

- 每一步时间
- 每个工具调用
- 每次文件变化
- 每次审批
- 每次审批结果
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
- DeepSeek API Agent
- MIMO API Agent
- Kimi / Qwen / Doubao API Agent
- OpenAI-compatible Provider
- 本地模型 Runtime

对用户来说，底层 Runtime 不同，但前台体验一致：

- 同样的会话列表
- 同样的 Timeline
- 同样的审批流
- 同样的日志结构
- 同样的 Diff 视图

### 6.5 在外面远程连接家里的 Mac

用户的 Mac 在家里运行 MacRelay，用户人在外面。

用户希望：

```text
打开 iPhone
选择家里的 Mac
连接 MacRelay
查看正在执行的 Agent
发送新任务
审批高风险操作
查看文件变更和执行结果
```

第一阶段推荐使用 Tailscale 方式完成，不直接暴露公网端口。

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

### 7.2 Timeline First

Agent 执行步骤不是普通日志，而是产品核心。

用户必须能清楚知道：

```text
Agent 做了什么
通过了什么
审批了什么
卡在哪里
下一步是什么
最终是否成功
```

因此，MacRelay 的核心视图应该从 Chat View 升级为：

```text
Chat + Run Timeline + Approval + File Diff
```

### 7.3 Runtime Provider 插件化

Codex、Claude Code、OpenAI API、DeepSeek API、MIMO API、本地模型都只是 Runtime Provider。

MacRelay 不应该把任何一个 Runtime 写死成核心逻辑。

### 7.4 Event 是事实，Snapshot 是结果

事件日志应该记录「发生了什么」。

Snapshot 只是由事件规约出来的当前状态，不应该替代事件本体。

### 7.5 手机端重在控制，不重在编辑

iPhone 不应该承担复杂开发环境的职责。

手机端最重要的是：

- 看状态
- 看变更
- 做审批
- 发轻量指令
- 接管关键决策

### 7.6 安全优先于便利

MacRelay 允许手机远程控制 Mac 上的 Agent，本质上具备高权限。

必须优先保证：

- 设备可信
- 操作可审计
- 权限可控
- 高风险动作可审批
- 配对可撤销
- 远程访问不裸奔

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
{"seq":4,"type":"approval.requested","timestamp":"2026-07-02T10:00:12Z","payload":{"tool":"write_file","path":"LoginView.swift","riskLevel":"medium"}}
{"seq":5,"type":"approval.resolved","timestamp":"2026-07-02T10:00:15Z","payload":{"decision":"allow_once"}}
{"seq":6,"type":"file.change.detected","timestamp":"2026-07-02T10:00:20Z","payload":{"path":"LoginView.swift","changeKind":"modified"}}
```

#### 验收标准

- 每个 session 自动生成 trace.jsonl
- 事件按 seq 严格递增
- trace 不依赖 UI 存在
- 异常退出也能保留已产生 trace
- trace 可以用于重建 snapshot
- trace 能完整回答「做了什么、通过了什么、审批了什么」

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

### 8.1.5 Run Timeline / Agent 行为审计视图

#### 需求描述

将当前「Agent 执行步骤」升级为结构化 Run Timeline。

这不是普通日志展示，而是 Agent 行为审计视图。用户需要非常清晰地知道：

```text
Agent 做了什么
通过了什么
审批了什么
改了什么
卡在哪里
失败在哪里
```

#### Timeline 示例

```text
1. 用户输入：修复登录页崩溃
2. Agent 分析：读取项目结构
3. 工具调用：read_file LoginView.swift
4. 工具调用：search_text "LoginState"
5. 审批请求：准备修改 LoginView.swift
6. 用户审批：允许一次
7. 文件变更：LoginView.swift +12 -4
8. 审批请求：准备执行 swift test
9. 用户审批：允许一次
10. 工具调用：run_shell_command swift test
11. 测试结果：通过
12. Agent 总结：已完成修复
```

#### Timeline 卡片类型

```text
User Message
Agent Analysis
Assistant Delta
Tool Call Requested
Tool Call Running
Tool Call Completed
Tool Call Failed
Approval Request
Approval Resolved
File Change
Diff Update
Error
Final Result
```

#### 每个步骤固定字段

```text
时间
步骤类型
状态：进行中 / 成功 / 失败 / 等待审批
Runtime：Codex / Claude Code / API Agent
工具名
输入参数
输出摘要
风险等级
审批状态
文件 Diff
错误信息
```

#### UI 要求

- 默认展示高层步骤，不淹没在底层日志里
- 工具参数可以折叠
- Diff 可以展开
- 审批请求必须高亮
- 失败步骤必须醒目
- 当前正在执行的步骤必须明显
- 已通过步骤要有明确完成状态
- 审批记录要能看出是谁、何时、批准了什么

#### 验收标准

- 用户能一眼看出 Agent 当前卡在哪里
- 用户能看到文件变更顺序
- 用户能区分普通消息和工具调用
- 用户能在 Timeline 中处理审批
- Timeline 与 trace 数据结构一致
- 用户能清楚回答「这个 Agent 到底做了什么」

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
- Timeline 中可以看到审批请求和审批结果

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
- 查看当前远程访问模式

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
- Trace -> Snapshot

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
- 关键 Probe 能被测试替代

---

## 8.2 V1.5：Remote Access Mode

### 8.2.1 目标

在局域网之外，让用户可以安全连接家中或办公室的 MacRelay。

典型场景：

```text
Mac 在家里运行 MacRelay
用户人在外面
iPhone 可以连接 MacRelay
用户可以查看 Agent 状态、发送任务、处理审批
```

---

### 8.2.2 连接模式

MacRelay 支持多种连接模式：

```text
Local LAN
Tailscale Remote
Cloudflare Tunnel
Cloud Relay
```

推荐路线：

```text
V1：Local LAN
V1.5：Tailscale Remote Mode
V2：Cloudflare Tunnel Mode
V3：Cloud Relay Mode
```

---

### 8.2.3 Local LAN Mode

当前模式。

特点：

```text
Mac 和 iPhone 在同一局域网
通过局域网 IP + HTTP/WebSocket 连接
适合家里、办公室、同一 Wi-Fi
```

优点：

```text
简单
低延迟
不依赖第三方服务
```

缺点：

```text
离开局域网后无法连接
不适合人在外面远程控制
```

---

### 8.2.4 Tailscale Remote Mode

#### 需求描述

Mac 和 iPhone 都安装 Tailscale，并登录同一个 tailnet。MacRelay 通过 Tailscale 分配的私有 IP 或 MagicDNS 域名连接。

#### 为什么优先推荐

Tailscale 适合第一版远程访问：

```text
安全
配置简单
不需要公网 IP
不需要路由器端口转发
适合个人项目
不用把 MacRelay 暴露给整个互联网
```

#### 产品表现

Mac 端设置中展示：

```text
Remote Access
- Local LAN: enabled
- Tailscale: detected / not detected
- Tailscale IP: 100.x.y.z
- MagicDNS Name: macbook.tailnet-name.ts.net
```

iPhone 端支持：

```text
添加远程 Mac
输入 Tailscale IP 或 MagicDNS
保存设备
使用 challenge-response 认证
```

#### 验收标准

- MacRelay 可以绑定 Tailscale IP 或允许 Tailscale 网络访问
- iPhone 在外网时可以通过 Tailscale 连接 MacRelay
- 仍然使用 device challenge-response 认证
- 不需要公网端口转发
- UI 清晰提示当前为 Tailscale Remote Mode

---

### 8.2.5 Cloudflare Tunnel Mode

#### 需求描述

通过 Cloudflare Tunnel 将 MacRelay 暴露为受保护的 HTTPS / WSS 入口。

适合后续更正式的远程访问体验。

#### 优点

```text
不需要公网 IP
不需要路由器端口转发
可以绑定域名
可以接 Cloudflare Access 登录保护
体验更像正式产品
```

#### 风险

```text
配置更复杂
需要 Cloudflare 账号
如果访问控制没做好，风险较高
```

#### 安全要求

```text
必须启用 Cloudflare Access 或等价访问控制
仍然保留 MacRelay 自身 challenge-response
不允许裸露无保护 WebSocket
必须支持 revoke tunnel
```

---

### 8.2.6 Cloud Relay Mode

#### 需求描述

MacRelay 自建云端中转服务：

```text
iPhone <-> Cloud Relay <-> MacRelay Desktop
```

Mac 主动连接 Cloud Relay，iPhone 也连接 Cloud Relay，由 Relay 转发消息。

#### 优点

```text
产品体验最好
不依赖用户安装 Tailscale
可以做账号体系、设备管理、在线状态
未来商业化更自然
```

#### 缺点

```text
工程复杂度最高
要处理认证、加密、重连、消息队列、成本
安全压力最大
```

#### 定位

Cloud Relay 不建议当前立刻做，适合作为 V3 或 V4。

---

### 8.2.7 不推荐：路由器端口转发

不建议用户通过路由器端口转发直接暴露 MacRelay。

原因：

```text
MacRelay 控制的是本地 Agent
具备文件写入和 Shell 命令执行能力
裸露公网端口风险太高
家庭网络环境差异大
用户很难正确配置安全策略
```

一句话：

> 把 MacRelay 直接暴露到公网，就是把门拆了再研究锁，很朋克，但不聪明。

---

## 8.3 V2：APIAgentRuntime

### 8.3.1 API Runtime 抽象

#### 需求描述

新增 APIAgentRuntime，用于接入 OpenAI / Anthropic / Gemini / DeepSeek / MIMO 等大模型 API。

#### Runtime 架构

```text
AgentRuntime
  ├── CodexRuntime
  ├── ClaudeCodeRuntime
  └── APIAgentRuntime
        ├── OpenAIRuntime
        ├── AnthropicRuntime
        ├── GeminiRuntime
        ├── DeepSeekRuntime
        ├── MIMORuntime
        └── OpenAICompatibleRuntime
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

### 8.3.2 Model Provider 管理

#### 需求描述

支持配置不同模型供应商。

#### Provider 类型

```text
OpenAI
Anthropic
Gemini
DeepSeek
MIMO
Mistral
Moonshot / Kimi
Qwen / 通义千问
Doubao / 豆包
OpenAI-compatible endpoint
Local model endpoint，例如 Ollama / LM Studio
```

#### 配置项

```text
providerID
displayName
providerType
baseURL
apiKey
model
maxTokens
temperature
supportsStreaming
supportsToolCalling
supportsVision
supportsReasoning
protocolType
```

#### Provider 抽象

不要为每家都写死逻辑，优先抽象为：

```text
Provider
  - name
  - baseURL
  - apiKey
  - model
  - protocolType
  - capabilities
```

对于 DeepSeek、MIMO、Kimi、Qwen 等兼容 OpenAI-style API 的 Provider，优先走：

```text
OpenAI-compatible endpoint
```

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
- OpenAI-compatible Provider 可以接入 DeepSeek / MIMO 等模型

---

### 8.3.3 Tool Registry

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

### 8.3.4 API Agent Loop

#### 需求描述

实现基础 Agent Loop。

#### 流程

```text
User Input
-> Build Context
-> Model Request
-> Stream Assistant Delta
-> Tool Call Requested
-> Approval Gate
-> Execute Tool
-> Tool Result
-> Continue Model Request
-> Final Answer
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
- Timeline

#### 验收标准

- 可以完成简单代码修改任务
- 可以读取文件
- 可以写文件
- 可以运行测试命令
- 手机端可以审批工具调用
- 完成后生成完整 Timeline

---

## 8.4 V3：Agent Spec

### 8.4.1 `.agent/agent.md`

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

### 8.4.2 `.agent/tools.json`

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

### 8.4.3 `.agent/policy.json`

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

### 8.4.4 `.agent/memory.md`

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
    - Remote Access Status
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
    - Remote Access
```

### 9.2 iPhone 端

```text
Home
  - Connection Status
  - Local Mac List
  - Remote Mac List
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
  - Remote Access
  - Runtime Providers
  - Approval Policy
```

---

## 10. 关键用户流程

### 10.1 配对流程

```text
Mac 启动 MacRelay
-> 生成 pairing URI / QR Code
-> iPhone 扫码
-> iPhone 调用 /pairing/claim
-> 获取 deviceID + deviceSecret
-> 存入 iPhone Keychain
-> WebSocket challenge-response 登录
-> 配对成功
```

### 10.2 远程执行流程

```text
iPhone 输入任务
-> WebSocket session.turn.start
-> MacRelay 转发给 Runtime
-> Runtime 产生 RuntimeEvent
-> MacRelay 记录 trace
-> MacRelay 广播事件
-> iPhone Timeline 更新
```

### 10.3 审批流程

```text
Runtime 请求工具调用
-> MacRelay 判断风险等级
-> 生成 approval.requested
-> iPhone 展示审批卡
-> 用户选择 allow / reject
-> approval.resolved 回传
-> Runtime 继续或终止
-> trace 记录审批结果
-> Timeline 展示审批结果
```

### 10.4 Replay 流程

```text
iPhone 断线
-> MacRelay 继续运行 Agent
-> iPhone 重连
-> 发送 replay.from afterSeq
-> 服务端返回缺失 events
-> iPhone 补齐 Timeline
-> 如果缓存不足，拉 snapshot
```

### 10.5 Tailscale 远程连接流程

```text
Mac 安装并登录 Tailscale
iPhone 安装并登录同一 Tailscale 账号
MacRelay 检测 Tailscale IP / MagicDNS
iPhone 添加远程 Mac 地址
iPhone 通过 Tailscale 网络连接 MacRelay
MacRelay 执行 challenge-response 认证
认证成功后进入远程控制
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

### 11.5 Remote Access Endpoint

```json
{
  "endpointID": "uuid",
  "name": "Home MacBook",
  "mode": "tailscale",
  "host": "macbook.tailnet-name.ts.net",
  "httpPort": 63165,
  "wsPort": 48732,
  "lastConnectedAt": "2026-07-02T10:00:00Z",
  "trustedDeviceID": "device_uuid"
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
remote.endpoint.list
remote.endpoint.add
remote.endpoint.remove
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
remote.connection.changed
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

### 13.3 LAN / Remote 暴露

Mac 端需要清晰展示：

- 当前监听地址
- HTTP port
- WebSocket port
- 是否监听 localhost
- 是否监听 LAN IP
- 是否启用 Tailscale Remote
- 是否启用 Cloudflare Tunnel
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

### 13.5 远程访问安全要求

```text
远程访问不得降低本地认证要求
Tailscale 模式仍必须使用 challenge-response
Cloudflare Tunnel 模式必须启用额外访问控制
不推荐路由器端口转发
不允许无认证 WebSocket
所有 remote endpoint 需要可删除、可重置
```

---

## 14. 非功能需求

### 14.1 性能

- assistant.delta 展示延迟 < 300ms
- WebSocket reconnect 后 2s 内恢复状态
- trace 写入不能阻塞主 UI
- 单 session 支持至少 10,000 条事件
- Timeline 滚动不卡顿

### 14.2 稳定性

- Runtime 崩溃不导致 MacRelay 崩溃
- iPhone 断线不影响 Mac Runtime 继续执行
- trace 写入失败要有 error event
- WebSocket 客户端异常断开要自动清理连接状态
- Tailscale 连接切换网络后可恢复

### 14.3 可维护性

- Codex / Claude / API Runtime 不能互相耦合
- UI 不直接依赖 Runtime 原始协议
- 事件 schema 需要版本号
- Probe 与 Test 数据要可复用
- Provider 接入优先走通用 OpenAI-compatible 抽象

### 14.4 可观测性

- 每个 session 有 metadata
- 每个 event 有 seq
- 每个 command 有 correlationID
- 每个 error 有 code + message
- 支持导出 trace
- Timeline 能展示关键行为路径

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
- trace 能回答「做了什么、通过了什么、审批了什么」

---

## Milestone 2：Replay & Run Timeline

目标：完成断线重连和结构化 Timeline。

范围：

- replay.from 完善
- needsFullSnapshot fallback
- Timeline 数据模型
- iOS Timeline UI
- Mac Timeline UI
- File Change 卡片
- Approval 卡片
- Error 卡片

验收：

- iPhone 断线后重连不丢事件
- 用户能看到完整执行步骤
- 用户能看到审批记录
- 用户能看到文件变更顺序
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
- 审批记录显示在 Timeline

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

## Milestone 5：Tailscale Remote Mode

目标：支持人在外面连接家里的 MacRelay。

范围：

- Remote Access 设置页
- Tailscale IP / MagicDNS 检测
- iPhone 添加远程 Mac
- Tailscale endpoint 存储
- 远程连接状态展示
- challenge-response 认证复用

验收：

- iPhone 不在同一局域网时，可以通过 Tailscale 连接 MacRelay
- 不需要路由器端口转发
- 认证仍然使用 challenge-response
- 用户能清楚知道当前处于 Tailscale Remote Mode

---

## Milestone 6：APIAgentRuntime MVP

目标：支持第一个 API Agent Runtime。

范围：

- OpenAI Provider
- OpenAI-compatible Provider
- DeepSeek / MIMO Provider 配置示例
- API Key Keychain 存储
- Model config
- Streaming response
- Tool Registry
- read_file / list_files / search_text / write_file / run_shell_command
- Approval Gate 接入
- Trace 接入

验收：

- 用户可以用 API Agent 完成一次简单代码修改
- DeepSeek / MIMO 等兼容接口可以接入
- 工具调用出现在 Timeline
- 文件变更出现在 Diff
- Shell 命令需要审批
- trace 完整记录全过程

---

## Milestone 7：Agent Spec

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
- 用户可以清楚知道 Agent 通过了什么步骤
- 用户可以阻止高风险操作
- 用户可以切换 Codex / Claude / API Runtime
- 用户可以在局域网外通过安全方式连接 MacRelay

### 16.2 技术指标

- RuntimeEvent 覆盖 90% 以上核心事件
- trace 可以 100% 重建 snapshot
- 核心 reducer 有自动化测试
- WebSocket 断线重连稳定
- Approval 关键路径有 integration test
- Tailscale Remote Mode 不降低认证强度
- OpenAI-compatible Provider 可以支持多个模型厂商

### 16.3 学习指标

这个项目的学习价值不在于「又做了一个 Agent」，而在于真正理解：

- Agent Runtime
- Tool Calling
- Approval Gate
- Trace / Replay / Snapshot
- State Reducer
- Runtime Provider
- Local Workspace
- Secure Remote Control
- Remote Access
- Model Provider Abstraction

---

## 17. 风险与应对

### 17.1 功能膨胀

风险：

API Runtime、MCP、多 Agent、插件市场、远程访问都很诱人，容易做散。

应对：

```text
V1 只做 Harness 基础设施
V1.5 只做 Tailscale Remote Mode
V2 再做 APIAgentRuntime MVP
V3 再做 Agent Spec
```

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
- LAN / Remote 状态提示
- 不推荐公网端口转发

---

### 17.3 Runtime 差异过大

风险：

Codex、Claude Code、OpenAI API、DeepSeek API、MIMO API 的事件结构不同，统一抽象可能变复杂。

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

### 17.5 远程访问误用

风险：

用户可能尝试把 MacRelay 直接暴露到公网。

应对：

- UI 不推荐端口转发
- 文档明确禁止裸露公网端口
- 默认只提供 Local LAN / Tailscale
- Cloudflare Tunnel 必须提示访问控制
- 所有远程模式仍保留 challenge-response

---

## 18. 当前最应该做的 6 件事

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

### 4. 做 Run Timeline / Agent 行为审计视图

UI 不要继续只像聊天窗口。

必须展示：

```text
做了什么
通过了什么
审批了什么
改了什么
失败在哪
```

### 5. 把 Probe 变成 Tests

否则项目会停留在「本机试过」阶段。

### 6. 设计 Tailscale Remote Mode

这是最适合个人项目的远程访问方案，比公网端口转发靠谱得多。

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
- iOS Run Timeline 初版
- Mac Run Timeline 初版

第 4 周：
- Approval Gate
- Risk Policy
- Trusted Device 管理初版

第 5 周：
- Probe 迁移到 Tests
- GitHub Actions CI

第 6 周：
- Tailscale Remote Mode
- Remote endpoint 管理
- 远程连接状态展示

第 7 周：
- OpenAI-compatible APIAgentRuntime MVP
- DeepSeek / MIMO Provider 配置
- Tool Registry
- API Agent Loop
```

---

## 20. 结论

MacRelay 下一阶段不应该急着变成 Pi / Craft 的复制品。

更好的路线是：

> 先把 MacRelay 做成稳定、可验证、安全、可远程访问的 Agent Harness；再把 Codex、Claude Code、API Agent 都作为 Runtime Provider 接进来。

真正的壁垒不是「接了几个模型」，而是：

- 统一 Runtime 抽象
- 完整 Trace / Replay / Snapshot
- 清晰 Run Timeline
- 安全 Approval Gate
- 本地 Workspace
- Trusted Device
- 安全 Remote Access
- 手机远程控制体验

这条路更难，但更有价值。

MacRelay 最终应该成为：

> 一个运行在 Mac 本地、可由 iPhone 安全控制、支持多 Runtime Provider、可记录、可回放、可审批、可远程访问的 Agent Harness。

这比「又一个 AI 编程聊天窗口」强得多。
