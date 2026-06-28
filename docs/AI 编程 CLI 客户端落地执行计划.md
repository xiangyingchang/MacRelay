# AI 编程 CLI 客户端落地执行计划

创建日期：2026-06-21  | 最后更新：2026-06-27

> **实现更新：**
> - 2026-06-27：M0 全部完成，M1 配对/中继/状态同步已完成

关联 PRD：[[AI 编程 CLI 客户端需求文档]]

关联 UI 基准：[[AI 编程 CLI 客户端 UI 设计基准]]

关联 Relay 技术设计：[[AI 编程 CLI 客户端 Mac Relay 技术设计]]

## 1. 执行目标

围绕 PRD 的两个核心目标推进：

- Mac 端提供高品味、可视化的 Codex CLI 操作客户端。
- iPhone 端通过局域网配对完整接手 Mac 上的 Codex CLI session 操作，同时保持 local-first 隐私模型。

执行策略：

- 先做 M0 技术验证，确认 Codex CLI 控制、局域网同步、diff、session 级配置、防休眠这些关键能力可行。
- 再做 M1 可试用产品原型。
- 最后做 M2 设计和体验打磨，对齐 Hermes Desktop / Lody 级别的产品品味。

## 2. 当前阶段

当前阶段：M0 技术验证。

M0 的目标不是做完整产品，而是验证最关键的不确定性：

- 能否稳定启动和控制 Codex CLI。
- 能否拿到 session 输出、等待输入、approval / permission prompt 等状态。
- 能否让 iPhone 在局域网内完整接手输入和决策。
- 能否用本地 Git 状态生成 diff 并同步到手机。
- 能否在 session 维度切换模型、reasoning effort、Plan mode、权限模式。
- Mac 能否常驻、防休眠、断线重连。

## 3. M0 任务拆解

### M0.1 本机环境与 Codex CLI 能力探查

目标：确认当前机器是否具备启动技术原型的基础条件。

任务：

- 检查 `codex` 是否安装。
- 检查 Codex CLI 版本。
- 检查 `codex --help`、`codex app-server --help`、`codex debug models` 等能力。
- 检查 Swift / Xcode 命令行环境。
- 判断优先使用 Codex app-server 还是 PTY 包装。

验收：

- 明确 Codex CLI 可执行路径和版本。
- 明确是否可用 app-server。
- 明确 Swift/Xcode 是否可用于 macOS/iOS 原型开发。
- 产出技术结论：M0 原型优先路线。

### M0.2 Mac 端 Codex Session 原型

目标：Mac 本地能启动 Codex CLI session，并收发输入输出。

任务：

- 建立最小 macOS 原型工程。
- 实现 Codex CLI detector。
- 实现 session 启动。
- 实现 stdout / stderr / PTY 输出采集。
- 实现用户输入写入。
- 记录 session 元数据。

验收：

- 能从 Mac 原型启动 Codex CLI。
- 能在原型 UI 或日志中看到 Codex 输出。
- 能从原型向 Codex 发送输入。
- session 异常退出时能显示状态。

### M0.3 Session 级配置原型

目标：验证模型、reasoning effort、Plan mode、权限模式等是否能作为 session 级运行配置。

任务：

- 验证启动前参数：
  - model
  - model_reasoning_effort
  - sandbox_mode
  - approval_policy
  - profile
- 验证运行中 slash command：
  - `/model`
  - `/plan`
  - `/permissions`
  - `/status`
- 记录哪些配置可热切换，哪些只能新 session 生效。

验收：

- 至少支持启动前选择模型、reasoning effort、权限模式。
- 至少支持运行中切换 Plan mode。
- 形成配置映射表。

### M0.4 Diff / 文件变更原型

目标：不依赖 Codex 输出格式，独立生成文件变更和 diff。

任务：

- 在 session 开始时记录 Git baseline。
- 读取 working tree 状态。
- 生成单文件 diff。
- 区分 session changes 和 session 前已有改动。
- 实现 approve、approve & stage、discard session changes、discard all file changes 的底层操作验证。

验收：

- 能展示 changed files。
- 能展示单文件 diff。
- 能 stage 单个文件。
- 能只丢弃本次 session 产生的变更。
- 不误删 session 前已有用户改动。

### M0.5 局域网配对与同步原型

目标：iPhone 能通过局域网连接 Mac，并同步 session。

任务：

- Mac 端启动本地 WebSocket 服务。
- Mac 端生成二维码。
- iPhone 扫码连接。
- 建立设备 token。
- 同步 session 列表、输出、输入、diff、配置状态。
- 实现 heartbeat 和断线重连。

验收：

- iPhone 能扫码连接 Mac。
- iPhone 能看到 Mac session 输出。
- iPhone 能发送输入到 Mac session。
- 断线后能自动重连并恢复最近状态。

### M0.6 Prompt / Approval 接管原型

目标：手机端能处理 Codex 的阻塞点。

任务：

- 识别 Codex 等待输入状态。
- 识别 permission / approval prompt。
- 识别 Plan mode 后的执行确认。
- iPhone 端显示待处理事项。
- iPhone 端发送确认、拒绝、继续执行、重试等操作。

验收：

- 至少跑通一个 Codex 等待输入场景。
- 至少跑通一个 Plan mode 计划后手机端继续执行场景。
- 如果 approval prompt 暂时无法结构化识别，需要明确 PTY 兜底方案。

### M0.7 Mac 常驻与防休眠原型

目标：保证手机端可以持续接手。

任务：

- macOS 菜单栏常驻。
- 主窗口关闭后保持服务。
- 配置“运行 session 时防休眠”。
- 配置“连接 iPhone 时防休眠”。
- App 退出、session 结束、设备断开后释放防休眠。

验收：

- Mac 主窗口关闭后 iPhone 仍可连接。
- 开启防休眠后长任务不中断。
- 退出 App 后防休眠状态被释放。

## 4. M0 里程碑

M0 通过标准：

- Mac 能启动和控制 Codex CLI。
- iPhone 能局域网配对并完整发送输入。
- iPhone 能看到输出、diff、session 状态。
- iPhone 能处理至少一种 Codex 阻塞点。
- 双端能切换至少三个 session 级配置。
- Mac 能常驻、防休眠、断线恢复。

M0 不要求：

- 完整精美 UI。
- App Store 分发。
- 多 CLI adapter。
- 云端中继。
- 团队协作。
- 完整历史搜索。

## 5. M1 任务预告

M1 目标：可日常试用的本地优先产品原型。

工程顺序：

1. 按 [[AI 编程 CLI 客户端 Mac Relay 技术设计]] 建立 Swift Package 和共享模型。
2. 实现 `CodexAppServerClient`，用 Swift 复刻 Node 探针能力。
3. 实现 `SessionStateReducer`、`SessionRegistry`、`EventStore`。
4. 实现 Mac App 内部 relay service，先供 Mac UI 订阅，不急于接 iPhone。
5. 按 [[AI 编程 CLI 客户端 UI 设计基准]] 搭建 Mac 三栏工作台。
6. 实现 session toolbar：模型、effort、Plan、权限模式、cwd。
7. 实现 WebSocket relay server 和本机模拟 client。
8. 实现二维码 pairing、device trust、设备吊销。
9. 实现 iPhone RelayClient、Session List、Session Workspace。
10. 实现 approval inbox。
11. 实现文件树、diff viewer、approve / stage / discard。
12. 实现 heartbeat、断线重连、snapshot、event replay。
13. 实现菜单栏常驻、防休眠、本地通知。
14. 打磨 Mac / iPhone UI 到 Hermes Desktop / Lody 参考水准。

M1 主要产品能力：

- Mac 主界面产品化。
- iPhone 主界面产品化。
- session toolbar。
- 文件树和 diff 面板。
- approval inbox。
- 可操作通知。
- 设备管理和吊销。
- 基础设置页。

## 6. M2 任务预告

M2 目标：体验打磨到高品味工具产品。

主要任务：

- 对齐 Hermes Desktop / Lody 级别的视觉和交互品质。
- 代码高亮、diff 浏览、终端输出打磨。
- 移动端小屏复杂操作优化。
- session 搜索和恢复。
- 第二个 CLI adapter，例如 Claude Code。
- 分发、签名、公证、更新机制。

## 7. 当前执行记录

### 2026-06-21

- 创建执行计划。
- 执行 M0.1 本机环境与 Codex CLI 能力探查。

#### M0.1 探查结果

本机环境：

- Codex CLI 已安装。
- Codex CLI 路径：`~/.npm-global/bin/codex`
- Codex CLI 版本：`codex-cli 0.141.0`
- Swift 命令行可用：Apple Swift 6.1.2
- 当前只有 Command Line Tools，没有完整 Xcode。`xcodebuild -version` 提示 active developer directory 是 `/Library/Developer/CommandLineTools`，不是完整 Xcode。

Codex CLI 能力：

- `codex --help` 显示支持 interactive CLI、`exec`、`resume`、`app-server`、`remote-control`、`debug models` 等命令。
- `codex app-server --help` 显示支持 `stdio://`、`unix://`、`ws://IP:PORT` 三类传输。
- `codex app-server daemon` 支持 start / restart / stop / enable-remote-control / version。
- `codex app-server generate-json-schema --experimental` 成功生成 app-server 协议 schema。
- schema 输出目录：`/private/tmp/codex-app-server-schema`
- schema 文件数量：329 个。

关键 schema 发现：

- `ThreadStartParams` 支持 `model`、`modelProvider`、`cwd`、`sandbox`、`approvalPolicy`、`permissions`、`personality`、`runtimeWorkspaceRoots`、`serviceTier` 等字段。
- `TurnStartParams` 支持对后续 turn 覆盖 `model`、`effort`、`cwd`、`approvalPolicy`、`permissions`、`sandboxPolicy`、`personality`、`serviceTier` 等字段。
- `ThreadSettingsUpdateParams` 支持更新后续 turn 的 `model`、`effort`、`approvalPolicy`、`permissions`、`sandboxPolicy`、`personality`、`serviceTier` 等字段。
- `TurnDiffUpdatedNotification` 提供 turn 级 unified diff。
- `CommandExecutionRequestApprovalParams` 提供结构化 command approval 请求，包括 command、cwd、reason、availableDecisions、additionalPermissions、networkApprovalContext 等。
- `codex debug models --bundled` 可输出模型 catalog，包含 `gpt-5.5`、reasoning levels、fast tier 等结构化信息。

初步技术结论：

- M0 原型优先路线应改为：优先验证 Codex app-server 协议，而不是直接 PTY 包装。
- PTY 仍作为兜底路线，用于 app-server 不稳定、协议缺字段、或需要兼容其他 CLI 工具时。
- Session 级配置可行性比预期更好：app-server schema 已支持 thread / turn 维度的 model、effort、approval、sandbox、permissions 更新。
- Diff 和 approval 也有结构化协议入口，可以先验证 app-server 通路，再决定是否需要客户端自建 diff / approval 解析层。
- 完整 macOS/iOS 原型开发需要安装或切换到完整 Xcode；当前 Command Line Tools 只适合做 Swift 命令行或协议探查。

#### M0.1 后续动作

- M0.2 调整为先做 app-server 最小协议客户端：启动 app-server、发起 thread、发送 turn、订阅通知。
- 同时保留 PTY 最小验证，作为 Codex CLI interactive fallback。
- 安装或切换完整 Xcode 后，再进入 SwiftUI macOS/iPhone App 工程。

#### M0.2 app-server 最小调用链

基于 schema，M0.2 可以先实现一个命令行协议客户端，不依赖完整 Xcode：

1. 启动 `codex app-server --stdio` 或 `codex app-server --listen ws://127.0.0.1:<port>`。
2. 发送 `initialize` 请求，clientInfo 使用本项目临时客户端名。
3. 发送 `initialized` 通知。
4. 发送 `thread/start`，带上 `cwd`、`model`、`sandbox`、`approvalPolicy` 等 session 级配置。
5. 发送 `turn/start`，带上用户输入、`model`、`effort`、`approvalPolicy`、`sandboxPolicy` 等 turn 级覆盖配置。
6. 监听 server notifications 和 server requests。

M0.2 重点监听：

- `thread/started`
- `thread/status/changed`
- `thread/settings/updated`
- `turn/diff/updated`
- `turn/plan/updated`
- `turn/started`
- `turn/completed`
- `item/command_execution/requestApproval`
- `item/file_change/requestApproval`
- `item/permissions/requestApproval`

M0.2 初步判断：

- app-server 协议已经覆盖本产品最关键的 session、turn、配置、diff、approval 能力。
- 下一步应该写一个最小 JSON-RPC 客户端验证真实收发，而不是马上做 UI。
- 如果 stdio 协议接入顺利，Mac App 可以内嵌 app-server 连接层；iPhone 通过 Mac 自建的本地 relay 协议消费结构化状态。

#### M0.2 探针执行结果

已创建临时探针脚本：

- `/private/tmp/codex_app_server_probe.mjs`

探针目标：

- 启动 `codex app-server --stdio`。
- 发送 `initialize`。
- 发送 `model/list`。
- 发送 `thread/start`。
- 发送 `turn/start`。
- 监听 notification / request。

第一次运行结果：

- app-server 需要写入 `~/.codex` 下的 sqlite 状态。
- 在受限沙箱内运行失败，错误为无法初始化 `~/.codex` state runtime。
- 使用授权运行后通过。

第二次运行结果：

- `initialize` 成功。
- `model/list` 成功。
- `thread/start` 失败，原因是 `sessionStartSource = "api"` 不符合 schema。当前版本只接受 `startup` 或 `clear`。

第三次运行结果：

- `initialize` 成功。
- `model/list` 成功，返回结构化模型列表。
- 返回模型包含：
  - `gpt-5.5`
  - `gpt-5.4`
  - `gpt-5.4-mini`
- 模型返回字段包含：
  - display name
  - default reasoning effort
  - supported reasoning efforts
  - service tiers / Fast
- `thread/start` 成功。
- `turn/start` 失败，原因是 `sandboxPolicy` 结构不对。turn 级 sandbox policy 需要 `{ "type": "readOnly" }`，而不是 CLI 参数风格的 `read-only`。

第四次运行结果：

- `initialize` 成功。
- `model/list` 成功。
- `thread/start` 成功。
- `turn/start` 成功。
- 收到 `thread/settings/updated`，包含：
  - cwd
  - approvalPolicy
  - approvalsReviewer
  - sandboxPolicy
  - model
  - modelProvider
  - effort
  - collaborationMode
  - personality
- 收到 `thread/status/changed`，可判断 active / idle。
- 收到 `turn/started` 和 `turn/completed`。
- 收到 `item/agentMessage/delta`，可流式拼接 assistant 输出。
- 收到 `item/completed`，可拿到最终 assistant message。
- 收到 `item/commandExecution/*`，说明 command execution 有结构化事件。
- 收到 token usage 和 rate limit 更新。

重要观察：

- app-server 协议链路真实可用，M0.2 通过。
- session 级配置和 turn 级覆盖真实生效，`thread/settings/updated` 能作为双端 session toolbar 的状态源。
- 模型列表、reasoning effort、Fast tier 可以通过 `model/list` 结构化获取，不需要硬编码。
- assistant 输出可通过 `item/agentMessage/delta` 流式同步到 iPhone。
- command execution 是结构化 item，未来可在 UI 中作为工具调用事件展示。
- 即使 prompt 写了“不检查或编辑文件”，模型仍可能主动执行命令；客户端不能假设纯问答 turn 不会有 command execution。
- app-server 写 `~/.codex` 是必要行为，Mac App 需要明确依赖 Codex 本地 state。

M0.2 结论：

- 优先 app-server 协议路线成立。
- PTY 应降级为 fallback，而不是第一实现路径。
- 下一步应验证三件事：
  - approval request 的真实触发和响应。
  - diff / file change 的真实通知。
  - `thread/settings/update` 对 active thread 后续 turn 的配置变更。

#### M0.2 专项验证结果

已创建临时专项探针脚本：

- `/private/tmp/codex_app_server_settings_probe.mjs`
- `/private/tmp/codex_app_server_diff_probe.mjs`
- `/private/tmp/codex_app_server_approval_probe.mjs`

##### Settings Update 验证

目标：

- 验证 `thread/settings/update` 能否作为 session toolbar 的底层能力。

结果：

- `thread/settings/update` 调用成功。
- `thread/settings/updated` 通知返回更新后的配置。
- 已验证可更新：
  - model：从 `gpt-5.5` 切到 `gpt-5.4-mini`
  - effort：切到 `high`
  - approvalPolicy：切到 `never`
  - sandboxPolicy：保持 `readOnly`
  - serviceTier
- 后续 `turn/start` 使用更新后的设置。

结论：

- session toolbar 的核心配置热切换可行。
- Mac 和 iPhone 双端可以把 `thread/settings/updated` 作为状态源。

##### Diff / File Change 验证

目标：

- 验证文件修改后是否有结构化 file change 和 turn diff。

测试仓库：

- `/private/tmp/codex-probe-repo`

结果：

- Codex 成功修改 `probe.txt`。
- 收到 `item/started` / `item/completed`，其中 item type 为 `fileChange`。
- fileChange item 包含：
  - file path
  - change kind
  - 单文件 diff
- 收到 `turn/diff/updated`，包含 turn 级 unified diff。
- `git diff -- probe.txt` 与 app-server diff 一致。

结论：

- iPhone diff 展示可以优先使用 app-server 的结构化 diff。
- 客户端仍应保留 Git working tree diff 作为校验和 fallback。
- `fileChange` item 比单纯解析命令输出更适合作为 UI 事件源。

##### Approval 验证

目标：

- 验证 read-only sandbox 下文件变更能否触发 approval request，并由客户端响应。

测试仓库：

- `/private/tmp/codex-approval-probe-repo`

结果：

- 在 read-only sandbox 下请求修改 `approval.txt`。
- 收到 `thread/status/changed`，activeFlags 包含 `waitingOnApproval`。
- 收到 server request：`item/fileChange/requestApproval`。
- 客户端回 JSON-RPC response：`{ "decision": "accept" }`。
- Codex 继续执行并完成文件修改。
- 收到 `turn/diff/updated`。
- 最终 `turn/completed`。

结论：

- 手机端 approval inbox 技术上可行。
- iPhone 可接手文件变更 approval。
- approval request / response 可以通过 Mac relay 转发到 iPhone。
- UI 需要展示 request 类型、文件路径、diff、可选 decision，并把结果回传 app-server。

#### M0.2 总结

M0.2 已通过。

app-server 已验证能力：

- thread start
- turn start
- model list
- settings update
- assistant streaming
- command execution event
- file change event
- turn diff
- approval request / response
- status changed

下一阶段建议：

- M0.3 从“验证配置是否可行”改为“整理 app-server 配置映射表和客户端状态模型”。
- M0.4 从“验证 diff 是否可行”改为“设计 diff manager：app-server diff 优先，Git diff fallback”。
- M0.5 可以开始做 Mac 本地 relay 原型：Mac 连接 app-server，iPhone 连接 Mac relay。

#### M0.5 Mac Relay 原型验证结果

时间：2026-06-21

目标：

- 验证 Mac 本地 relay 是否能把 iPhone 客户端请求转发到 Codex app-server。
- 验证移动端是否能通过同一条链路完成 session 创建、配置更新、消息输入、流式输出同步和 approval 处理。

临时原型：

- `/private/tmp/codex_mobile_relay.mjs`
- `/private/tmp/codex_mobile_sim_client.mjs`
- `/private/tmp/codex_mobile_sim_approval_client.mjs`

原型协议：

- Mac relay 启动 `codex app-server --stdio`。
- relay 对移动端暴露本地 HTTP + SSE 接口。
- `GET /state` 获取当前状态快照。
- `GET /events` 订阅事件流。
- `POST /command` 发送移动端命令。
- 已验证 command 类型：
  - `startThread`
  - `sendTurn`
  - `updateSettings`
  - `resolveApproval`

基础 session 验证：

- relay 监听 `127.0.0.1:48123`。
- 模拟移动端通过 SSE 连接 relay。
- 模拟移动端发起 `startThread`。
- 模拟移动端发起 `updateSettings`，将 session 更新为：
  - model: `gpt-5.4-mini`
  - effort: `low`
  - approvalPolicy: `never`
  - sandbox: `readOnly`
- 模拟移动端发起 `sendTurn`。
- relay 收到并转发 Codex assistant streaming。
- 最终收到 `turn/completed`、settings 同步和 token usage。

Approval 接管验证：

- 模拟移动端创建新 thread。
- 在 read-only sandbox 下请求 Codex 创建 `relay-approval-probe.txt`。
- Codex app-server 触发 `item/commandExecution/requestApproval`。
- relay 将 approval request 规范化为 `approval.requested` 事件并推送给移动端。
- 模拟移动端通过 `resolveApproval` 返回 `accept`。
- Codex 继续执行并完成文件写入。
- relay 收到最终 assistant message、`turn/completed` 和 `thread/status/changed`。

结论：

- M0.5 的核心链路可行。
- iPhone 不需要直接理解 Codex app-server 的完整 JSON-RPC 细节，可以通过 Mac relay 接收规范化事件。
- Mac relay 应成为正式架构中的核心同步层：负责连接 Codex app-server、维护 session 状态、转发输入、广播输出、桥接 approval。
- 第一版可以使用 HTTP + SSE 快速实现；正式版可在评估后升级为 WebSocket。
- approval inbox 的关键事件模型已经验证：
  - relay 保存 pending approval。
  - iPhone 展示待处理项。
  - iPhone 发回 accept / reject。
  - relay 将结果回写 app-server request。

遗留问题：

- 当前原型只验证了本机回环地址，尚未验证真实局域网设备发现、二维码配对和断线重连。
- 当前 approval 验证覆盖了 command execution approval；仍需补测 fileChange approval 在 relay 层的完整转发。
- 需要把原型从 Node 脚本迁移为 Mac App 内的长期运行服务。
- 需要补充 relay 的鉴权、设备 token、会话级权限控制和事件重放。

#### UI 参考调研与设计基准

时间：2026-06-21

已确认参考：

- Hermes Desktop / Hermes One：
  - 源码仓库：<https://github.com/fathah/hermes-desktop>
  - 技术栈：Electron / Vite / React / Tailwind。
  - 产品能力：streaming chat UI、SSE streaming、tool progress、markdown rendering、syntax highlighting、token usage、session management、profiles、models、tools、skills、settings。
- Lody：
  - 官网：<https://lody.ai/>
  - 文档：<https://lody.ai/docs>
  - 产品能力：worktree isolation、in-context diff、real-time file tree、mobile-first、approval from phone、daemon mode、session tabs、diff viewer、notifications。
  - 隐私差异：Lody 隐私政策显示会收集 conversation content 和 workflow context，并使用第三方基础设施；本产品第一版坚持 local-first 和局域网直连。

已产出：

- 新增 UI 设计基准文档：[[AI 编程 CLI 客户端 UI 设计基准]]
- PRD 已添加 UI 基准链接。
- M1 任务已明确需要按 UI 基准搭建 Mac / iPhone 信息架构。

设计结论：

- 后续 UI 不做普通聊天软件，也不做营销型界面。
- Mac 采用高密度三栏工作台：session/project rail + conversation/event stream + session inspector。
- iPhone 采用小屏任务流：session list + session workspace + diff/approval/settings sheets。
- session toolbar 必须贴近输入区，且所有配置都是 session 级状态。
- diff、approval、文件树、权限状态是核心工作区内容，不是二级设置页。

#### Mac Relay 技术设计

时间：2026-06-21

已产出：

- 新增技术设计文档：[[AI 编程 CLI 客户端 Mac Relay 技术设计]]
- PRD 已添加 Relay 技术设计链接。
- 执行计划已添加 Relay 技术设计链接。
- M1 任务预告已从产品功能列表补充为工程实现顺序。

关键设计结论：

- Mac Relay 是产品核心运行层，不是简单网络转发器。
- Codex app-server 只由 Mac Relay 通过 stdio 管理，不直接暴露给局域网。
- iPhone 通过 Mac Relay 消费归一化事件，不直接理解 Codex app-server 完整协议。
- M1 阶段 Relay 先作为 Mac App 进程内 Swift service / actor；后续再评估 LaunchAgent / helper daemon。
- 正式移动端协议建议使用 WebSocket + JSON envelope，支持 command response correlation、heartbeat、snapshot 和 event replay。
- Relay 状态模型需要覆盖 session、settings、approval、diff、device、connection。
- app-server diff 优先，Git working tree diff 作为校验和 fallback。

#### Xcode 安装与 Swift app-server 探针

时间：2026-06-21

环境更新：

- Xcode 已安装：`/Applications/Xcode.app`
- `xcode-select` 已指向：`/Applications/Xcode.app/Contents/Developer`
- Xcode 版本：`Xcode 26.5`
- Build version：`17F42`
- Swift 版本：Apple Swift `6.3.2`
- Xcode license 已接受。

已创建临时 Swift 探针：

- `/private/tmp/AgentClientSwiftProbe`

编译结果：

- `swift build` 通过。
- 完整 Xcode 修复了此前 Command Line Tools 下 SwiftPM manifest / PackageDescription 链接失败的问题。

运行结果：

- Swift 探针成功启动 `codex app-server --stdio`。
- 成功发送 `initialize`。
- 成功发送 `model/list`。
- 成功读取模型列表，包含：
  - `gpt-5.5`
  - `gpt-5.4`
  - `gpt-5.4-mini`
- 成功发送 `thread/start`。
- 成功发送 `turn/start`。
- 成功收到：
  - `thread/started`
  - `thread/settings/updated`
  - `thread/status/changed`
  - `turn/started`
  - `item/agentMessage/delta`
  - `thread/tokenUsage/updated`
  - `account/rateLimits/updated`
  - `turn/completed`
- assistant streaming 返回：`swift app-server probe ok`

技术结论：

- Swift 侧直接接入 Codex app-server 可行。
- `codex app-server --stdio` 当前可按 newline-delimited JSON 读取，不需要 LSP `Content-Length` framing。
- `Process` + `Pipe` + line buffer 足以实现第一版 `CodexAppServerClient`。
- `CodexAppServerClient` 可以在 M1 中优先落地为 Swift actor / service。
- M1 不需要先引入 Node relay；Node 探针只保留为验证脚本参考。

后续动作：

- 把 Swift 探针沉淀为正式工程中的 `CodexAppServerClient`。
- 抽出 JSON-RPC envelope、pending request map、server request handler、notification reducer。
- 增加 approval request 的 Swift 端响应验证。
- 增加 diff / fileChange 的 Swift 端事件解析验证。

#### M1 近期工程切片

时间：2026-06-21

目标：从一次性 Swift 探针过渡到可复用的核心工程层。

切片 1：`CodexAppServerClient` 原型包

- 建立 Swift Package。
- 拆出 library target：`AgentClientCore`。
- 拆出 executable target：`CodexClientProbe`。
- 在 core 中实现：
  - line-delimited JSON reader
  - JSON-RPC request / notification / response writer
  - pending request id 生成
  - app-server process lifecycle
  - server response / request / notification / stderr / exit 事件分发
- executable 只负责演示调用链。

验收：

- `swift build` 通过。
- probe 能完成 `initialize -> model/list -> thread/start -> turn/start`。
- probe 能收到 assistant delta 和 `turn/completed`。

执行结果：

- 已创建结构化 Swift Package：
  - `/private/tmp/AgentClientCorePrototype`
- package targets：
  - library：`AgentClientCore`
  - executable：`CodexClientProbe`
- `AgentClientCore` 已拆出：
  - `LineDelimitedJSONBuffer`
  - `JSONRPCWriter`
  - `CodexAppServerClient`
  - `CodexAppServerEvent`
- `swift build` 通过。
- `CodexClientProbe` 可启动 `codex app-server --stdio`。
- 已验证调用链：
  - `initialize`
  - `model/list`
  - `thread/start`
  - `turn/start`
  - `thread/started`
  - `thread/settings/updated`
  - `thread/status/changed`
  - `turn/started`
  - `account/rateLimits/updated`
  - `error`
  - `turn/completed`
- 本次结构化 probe 运行时账号侧返回 `usageLimitExceeded`，所以没有重新收到 assistant delta；这属于账号额度/限额状态，不是 app-server 客户端协议失败。
- assistant delta 已在前一版单文件 Swift 探针中验证通过。

结论：

- `CodexAppServerClient` 的第一层工程拆分成立。
- 后续正式工程可以从 `/private/tmp/AgentClientCorePrototype` 迁移核心代码。
- 客户端状态模型必须把 `account/rateLimits/updated` 和 `error.codexErrorInfo = usageLimitExceeded` 作为一等状态处理，并在 UI 上明确展示“额度不足 / 稍后重试 / 升级或购买 credits”。

切片 2：Swift approval 验证

- 在 core 中支持 server request response。
- 复刻此前 Node approval probe。
- 在 read-only sandbox 下触发 approval。
- Swift probe 返回 accept / reject。

验收：

- Swift 端可接收 `requestApproval`。
- Swift 端可回写 JSON-RPC response。
- Codex 可继续执行或拒绝执行。

执行结果：

- 已在 `/private/tmp/AgentClientCorePrototype` 中新增：
  - `CodexApprovalRequest`
  - `CodexApprovalProbe`
- `CodexApprovalRequest` 负责把 app-server server request 归一化为 approval summary，同时保留 raw params。
- `CodexApprovalProbe` 在 read-only sandbox 下请求 Codex 创建文件：
  - `/private/tmp/codex-swift-approval-probe-repo/swift-approval-probe.txt`
- Swift probe 成功收到：
  - assistant delta
  - `thread/status/changed`，activeFlags 包含 `waitingOnApproval`
  - `item/commandExecution/requestApproval`
- Swift probe 成功回写 JSON-RPC response：
  - `{ "decision": "accept" }`
- Codex app-server 接受 response 后继续执行。
- 文件成功创建，大小 23 bytes。
- 最终收到 `turn/completed`，状态为 completed。
- 验证结束后无 `codex app-server` 残留进程。

结论：

- Swift 端 approval request / response 链路完整可行。
- iPhone approval inbox 可以建立在 Mac Relay 的同一套机制上：
  - Relay 收到 app-server server request。
  - Relay 保存 pending approval。
  - iPhone / Mac UI 展示 approval。
  - 任一端返回 accept / reject。
  - Relay 回写原始 JSON-RPC request id。
- 当前实测 `availableDecisions` 可能为空；客户端不能只依赖该字段展示按钮，需要根据 request type 提供默认 accept / reject，同时保留 raw data。
- request id 可能为 `0`；实现不能用 truthy 判断丢掉 id。

切片 3：Swift diff / fileChange 验证

- 在 core 中识别 `turn/diff/updated`。
- 在 core 中识别 `fileChange` item。
- 输出统一的 `DiffUpdated` / `FileChangeUpdated` 事件。

验收：

- Swift 端可拿到 turn 级 diff。
- Swift 端可拿到单文件 change 信息。
- 后续可接入 UI 的 Files / Diff 面板。

执行策略：

- 当前 Codex 账号额度可能不足，因此先进入“额度保护模式”。
- 先做不消耗模型额度的工程化工作：
  - 在 Swift core 中实现 diff / fileChange 事件模型。
  - 用本地 JSON 样例验证 parser。
  - `swift build` 验证编译。
- 暂不主动运行会触发模型调用的真实 `turn/start` diff probe。
- 真实 app-server diff 验证留到额度恢复后执行。

可交接状态：

- 如果切换到其他工具继续，优先接手 `/private/tmp/AgentClientCorePrototype`。
- 当前核心 target：`AgentClientCore`。
- 当前已验证：
  - app-server lifecycle
  - JSON-RPC request / notification / response
  - assistant streaming
  - approval request / response
- 下一步应避免先调用 Codex 模型，先补 parser 和本地测试。

执行结果：

- 已在 `/private/tmp/AgentClientCorePrototype` 中新增：
  - `CodexTurnDiffUpdated`
  - `CodexFileChangeUpdated`
  - `CodexDiffFixtureProbe`
- `CodexTurnDiffUpdated` 支持解析：
  - `turn/diff/updated`
  - `threadId`
  - `turnId`
  - unified diff
  - changed file list
- `CodexFileChangeUpdated` 支持解析：
  - `item/started`
  - `item/completed`
  - item type = `fileChange`
  - path / filePath / uri / changes 中的路径
  - changeKind / kind / status
  - diff / unifiedDiff
- `swift build` 通过。
- `CodexDiffFixtureProbe` 本地样例验证通过，不调用 Codex、不消耗额度。
- fixture 输出确认：
  - turn diff 可识别 `Sources/App.swift`
  - fileChange 可识别 path、changeKind、diffLength、threadId、turnId。

未执行项：

- 未运行真实 app-server diff probe，原因是当前 Codex 额度可能不足。
- 待额度恢复后再执行真实验证：
  - 触发 Codex 修改 `/private/tmp` 测试仓库。
  - 确认 Swift core 能从真实事件解析 `turn/diff/updated`。
  - 确认 Swift core 能从真实 `fileChange` item 解析单文件变更。

结论：

- Swift core 已具备接 UI 的 diff / fileChange 基础模型。
- 当前解析器对字段名保持宽松，适合 app-server 协议仍在变化的阶段。
- 下一步在不消耗额度的情况下，可以继续做 `SessionStateReducer`，把 notification 归并为 session snapshot。

#### Claude Code 辅助任务：SessionStateReducer 设计

时间：2026-06-21

任务：

- 让 Claude Code 只输出建议，不修改文件。
- 目标是为 M1 草拟最小 `SessionStateReducer`。
- 调用使用授权网络环境。
- 模型：`deepseek-v4-flash`。

Claude 输出要点：

- 建议建立 `SessionSnapshot`、`TurnState`、`ApprovalState`、`DiffState`。
- 建议 reducer 做纯函数。
- 建议优先支持：
  - `turn/started`
  - `turn/completed`
  - approval request
  - `item/completed` 中的 `fileChange`
  - `turn/diff/updated`
  - assistant delta
- 建议 M1 不做复杂历史、持久化、非 fileChange item 追踪、stderr 解析、重连恢复。

主 Agent 审阅修正：

- Claude 把 approval 当作 notification 处理，这与实测不一致；真实 app-server approval 是 server request，需要用 request id 回 JSON-RPC response。
- Claude 建议只记录当前 turn；M1 可以接受，但 snapshot 还必须纳入：
  - thread id
  - cwd
  - session status
  - settings
  - rate limit
  - app-server error
- Claude 的建议可作为 reducer 范围参考，但实现必须以此前 Swift / Node 实测协议为准。

执行结果：

- 已在 `/private/tmp/AgentClientCorePrototype` 新增：
  - `SessionStateReducer`
  - `SessionSnapshot`
  - `TurnSnapshot`
  - `ApprovalSnapshot`
  - `FileChangeSnapshot`
  - `SessionSettingsSnapshot`
  - `SessionErrorSnapshot`
  - `RateLimitSnapshot`
  - `SessionReducerFixtureProbe`
- reducer 支持把 `CodexAppServerEvent` 映射为 `SessionReducerAction`。
- 当前支持事件：
  - `thread/started`
  - `thread/status/changed`
  - `thread/settings/updated`
  - `turn/started`
  - `item/agentMessage/delta`
  - `turn/completed`
  - server request approval
  - `turn/diff/updated`
  - `fileChange`
  - `account/rateLimits/updated`
  - `error`
  - process `exit`
- `swift build` 通过。
- `SessionReducerFixtureProbe` 本地 fixture 验证通过，不调用 Codex、不消耗额度。

fixture 输出确认：

- `assistantText` 合并为 `hello world`。
- request id `0` 的 approval 可进入 snapshot，并可被标记为 `accept`。
- `turn/diff/updated` 可提取 changed file：`file.txt`。
- `fileChange` 可进入 `fileChanges`。
- settings 可提取 model / effort / cwd。
- rate limit 可提取 planType / limitId。
- turn completed 后 session status 为 `completed`。

结论：

- M1 的第一版 session snapshot reducer 已可用。
- 后续 Mac UI 和 iPhone relay 都应该消费 `SessionSnapshot`，而不是直接消费 Codex 原始事件。
- 下一步可以继续在不消耗额度的情况下做 `RelayProtocol` envelope 和 snapshot/replay 模型。

#### Claude Code 辅助任务：RelayProtocol 草案与主 Agent 收敛实现

时间：2026-06-21

任务：

- 让 Claude Code 生成 RelayProtocol envelope + snapshot/replay 的纯 Swift 类型草案。
- 约束：不做 UI、不改文件、Foundation only。
- 调用模型：`deepseek-v4-flash`。

Claude 输出要点：

- 建议 `RelayEnvelope`。
- 建议 `RelayCommand` / `RelayEvent`。
- 建议 `ConnectionSnapshot`、`ReplayRequest`、`SnapshotPayload`。
- 建议 event sequence 和 fixture probe。

主 Agent 审阅修正：

- Claude 草案过度设计了 M1 不需要的能力：
  - compression
  - HMAC signature
  - channel routing
  - suspend / resume / replaySeek 等复杂 replay 控制
- M1 当前需要的是局域网 relay 的最小 wire model：
  - envelope
  - message id
  - type
  - version
  - sequence number
  - correlation id
  - snapshot payload
  - replay from last sequence
- 安全签名、压缩、多 channel、复杂 replay 控制后移，避免第一版协议负担过重。

执行结果：

- 已在 `/private/tmp/AgentClientCorePrototype` 中新增：
  - `RelayProtocol`
  - `RelayEnvelope`
  - `RelayCommandType`
  - `RelayEventType`
  - `ConnectionSnapshotPayload`
  - `RelaySnapshotPayload`
  - `RelaySessionSnapshotPayload`
  - `RelayApprovalPayload`
  - `RelayReplayRequestPayload`
  - `RelayEventRecord`
  - `RelaySequence`
  - `RelayProtocolFixtureProbe`
- `swift build` 通过。
- `RelayProtocolFixtureProbe` 本地验证通过，不调用 Codex、不消耗额度。

fixture 输出确认：

- 可把 `SessionSnapshot` 转成 `RelaySnapshotPayload`。
- 可生成 `session.snapshot` envelope。
- 可分配 sequence number。
- 可 JSON encode / decode。
- 可生成 `replay.from` command，并用 `correlationID` 关联 snapshot envelope。

结论：

- M1 relay 协议最小模型已可用。
- iPhone 初次连接后可以先消费 `session.snapshot`。
- iPhone 断线重连时可发送 `replay.from`，携带 `afterSeq`。
- Relay 如果有事件缓存则 replay；缓存不足则重新发完整 snapshot。
- 下一步可以继续做本地 `EventStore` / replay buffer，仍然不需要消耗 Codex 额度。

#### Claude Code 辅助任务：EventStore / Replay Buffer

时间：2026-06-21

任务：

- 让 Claude Code 草拟 EventStore / replay buffer。
- 约束：不做 UI、不改文件、Foundation only、M1 最小实现。
- 调用模型：`deepseek-v4-flash`。

Claude 输出要点：

- 建议固定容量 buffer。
- 建议 FIFO eviction。
- 建议 replay after sequence。
- 建议 `ReplayResult.events` / `needsFullSnapshot`。
- 建议缓存不足时回 full snapshot。

主 Agent 审阅修正：

- Claude 草案没有处理 `RelayEventRecord<Payload>` 的泛型异构存储问题。
- 实际 event store 需要保存不同 payload 类型的 envelope。
- 主 Agent 收敛为 type-erased 存储：
  - `StoredRelayEvent`
  - 保存 `seq`、`envelopeID`、`type`、`version`、`timestamp`、`payloadData`
  - replay 时返回 `StoredRelayEvent`
  - 需要时再按具体 payload 类型 decode
- M1 暂不做磁盘持久化、SQLite、去重、复杂过滤、AsyncSequence。

执行结果：

- 已在 `/private/tmp/AgentClientCorePrototype` 中新增：
  - `EventStore`
  - `StoredRelayEvent`
  - `EventReplayResult`
  - `EventStoreFixtureProbe`
- `swift build` 通过。
- `EventStoreFixtureProbe` 本地验证通过，不调用 Codex、不消耗额度。

fixture 输出确认：

- capacity = 3 时，append seq 1...5 后只保留 seq 3...5。
- `replay(afterSeq: 3)` 返回 seq 4、5。
- `replay(afterSeq: 0)` 返回当前缓存窗口 seq 3、4、5。
- `replay(afterSeq: 5)` 返回空 events，表示已追到最新。
- `replay(afterSeq: 1)` / `replay(afterSeq: 2)` 返回 `needsFullSnapshot`，表示客户端断线太久，缓存窗口不够。
- `replay(afterSeq: 99)` 返回 `needsFullSnapshot`，表示请求序号超过 relay 已知最新事件。
- `maxEvents` 截断有效。

结论：

- M1 的 replay buffer 已有最小可用实现。
- iPhone 重连策略可以是：
  1. iPhone 带 `lastSeenSeq` 发 `replay.from`。
  2. Relay 调 `EventStore.replay(afterSeq:)`。
  3. 如果返回 events，按顺序推送缺失事件。
  4. 如果返回 `needsFullSnapshot`，重新发送 `session.snapshot`。
- 下一步可以把 `SessionStateReducer`、`RelayProtocol`、`EventStore` 串成一个本地 `RelayCoreFixtureProbe`，模拟从 Codex event 到 snapshot/event store/replay 的完整链路。

#### Relay Core 本地闭环验证

时间：2026-06-21

目标：

- 不调用 Codex，不消耗额度。
- 在本地 fixture 中串联：
  - `SessionStateReducer`
  - `RelayProtocol`
  - `RelaySequence`
  - `EventStore`
- 验证从 Codex app-server 原始事件到 iPhone 可消费 relay snapshot / replay 的核心路径。

执行结果：

- 已在 `/private/tmp/AgentClientCorePrototype` 新增：
  - `RelayCoreFixtureProbe`
- `swift build` 通过。
- `RelayCoreFixtureProbe` 本地运行通过。

fixture 模拟输入：

- `thread/started`
- `thread/settings/updated`
- `turn/started`
- 两段 `item/agentMessage/delta`
- server request approval，request id = `0`
- `turn/diff/updated`
- `item/completed` with `fileChange`
- `turn/completed`

fixture 输出确认：

- 最终 `session.snapshot`：
  - status = `completed`
  - assistantText = `hello relay`
  - changedFiles = `file.txt`
  - pendingApprovals = `1`
  - lastEventSeq = `9`
- `EventStore`：
  - count = `9`
  - oldestSeq = `1`
  - newestSeq = `9`
- `replay(afterSeq: 3)` 返回：
  - seq 4：`turn.delta`
  - seq 5：`turn.delta`
  - seq 6：`approval.requested`
  - seq 7：`diff.updated`
  - seq 8：`fileChange.updated`
  - seq 9：`turn.completed`
- `replay(afterSeq: newestSeq)` 返回空 events，表示客户端已追到最新。

技术结论：

- Relay core 的最小本地闭环成立。
- iPhone 初次连接可消费 `session.snapshot`。
- iPhone 断线重连可用 `replay.from(afterSeq:)` 获取缺失事件。
- 如果 replay buffer 不足，则 fallback 到完整 snapshot。
- M1 进入 Mac App 工程骨架前，核心协议、状态、replay 的风险已经明显下降。

下一步建议：

- 开始搭建正式 Swift Package / Mac App 工程骨架。
- 将 `/private/tmp/AgentClientCorePrototype` 中已经验证的 core 文件迁移到正式工程。
- 第一版 Mac App 可以先只展示本地 fixture / mock session snapshot，不急于接真实 Codex。
- 接真实 Codex 时复用已验证的 `CodexAppServerClient`。

#### M1 正式工程骨架

时间：2026-06-21

目标：

- 从零散技术 prototype 过渡到 M1 工程骨架。
- 先建立可编译的 Swift Package。
- 先迁移已验证 core，不急于做正式 UI。

工程位置：

- `/private/tmp/AgentClientM1Prototype`

package targets：

- `AgentClientCore`
- `AgentClientMacMock`
- `RelayCoreFixtureProbe`

已迁移 core 文件：

- `CodexAppServerClient.swift`
- `JSONRPCWriter.swift`
- `LineDelimitedJSONBuffer.swift`
- `CodexApprovalRequest.swift`
- `CodexDiffEvents.swift`
- `SessionStateReducer.swift`
- `RelayProtocol.swift`
- `EventStore.swift`

新增说明：

- `README.md`
- 明确当前工程骨架暂不做 UI 品味设计。
- UI 和交互质量将单独基于 Hermes Desktop / Lody 参考设计。

验证结果：

- `swift build` 通过。
- `RelayCoreFixtureProbe` 通过，输出与原 core prototype 一致：
  - status = `completed`
  - assistantText = `hello relay`
  - changedFiles = `file.txt`
  - lastEventSeq = `9`
  - replay after seq 3 返回缺失事件。
- `AgentClientMacMock` 通过，可输出一个 `session.snapshot` JSON：
  - activeSessionID = `mock-thread`
  - status = `completed`
  - model = `gpt-5.5`
  - effort = `low`
  - assistantText = `AgentClient Mac mock ready.`
  - lastEventSeq = `5`

结论：

- M1 工程骨架已成立。
- 后续应以 `/private/tmp/AgentClientM1Prototype` 为主要工程入口。
- `/private/tmp/AgentClientCorePrototype` 可以继续作为历史验证参考，但不再作为主线。
- 下一步可以开始 `AgentClientMacMock` -> Mac SwiftUI shell 的过渡。

下一步建议：

- 新增 `AgentClientMacShell` 目标或 Xcode App target。
- 先展示 mock session snapshot，不接真实 Codex。
- Mac UI 第一屏按 [[AI 编程 CLI 客户端 UI 设计基准]] 的三栏工作台走：
  - left rail：session/project list
  - center：event stream
  - right inspector：files/diff/approval/settings placeholder
  - bottom composer + session toolbar
- UI 设计由主 Agent 亲自把关，不交给 DeepSeek / Claude 做最终品味判断。

#### Mac SwiftUI Shell 骨架

时间：2026-06-21

目标：

- 在 M1 工程骨架中加入可编译的 Mac shell。
- 先接 mock snapshot，不接真实 Codex，不消耗额度。
- 先验证三栏工作台结构和数据流，不把这一版视为最终视觉设计。

实现位置：

- `/private/tmp/AgentClientM1Prototype`

新增内容：

- `AgentClientMacShell` executable target。
- `MockSnapshotFactory`，用于生成统一 mock `RelaySnapshotPayload`。
- `AgentClientMacMock` 改为复用 `MockSnapshotFactory`。

Mac shell 当前结构：

- 左栏：CLI / Mac 在线状态、项目路径、session row。
- 中栏：session toolbar、conversation stream、inline approval、composer。
- 右栏：files、approvals、settings inspector。

设计约束：

- 这是工程骨架，不是最终视觉稿。
- 不交给 DeepSeek / Claude 做 UI 品味判断。
- 后续视觉和交互细节继续按 [[AI 编程 CLI 客户端 UI 设计基准]] 打磨。
- 先保持原生 SwiftUI + 高密度工作台方向，避免营销化或聊天软件化。

验证结果：

- `swift build` 通过。
- 首次编译失败原因：package 未声明 macOS deployment target，SwiftPM 默认使用过老 macOS 目标，导致 SwiftUI availability 报错。
- 已修复：`Package.swift` 增加 `platforms: [.macOS(.v14)]`。
- `AgentClientMacMock` 通过，输出 mock `session.snapshot` JSON。
- `RelayCoreFixtureProbe` 通过。
- 没有启动 GUI 进程；本阶段只做编译验证，避免在未完成 App bundle / window lifecycle 前引入不稳定因素。

当前 mock snapshot 覆盖：

- model = `gpt-5.5`
- effort = `low`
- status = `completed`
- assistantText = `AgentClient Mac mock ready.`
- changedFiles = `Sources/App.swift`
- pending approval request id = `0`
- command = `/bin/zsh -lc swift build`
- lastEventSeq = `8`

结论：

- M1 已具备从 core 到 Mac shell 的第一条编译链路。
- 下一步可以开始把 `AgentClientMacShell` 从 SwiftPM executable 迁移为真正的 Xcode macOS App target，或继续在 SwiftPM 中补 Mock UI 状态。
- 真正接 Codex 之前，建议先完成 Mac shell 的状态绑定和基本交互占位。

#### Mac SwiftUI Shell 状态绑定与交互占位

时间：2026-06-21

目标：

- 继续在不接真实 Codex 的前提下推进 Mac shell。
- 从静态 snapshot 展示过渡到本地 ViewModel 状态绑定。
- 为 session toolbar、composer、approval 操作建立交互占位。

实现位置：

- `/private/tmp/AgentClientM1Prototype`

实现内容：

- `AgentClientMacShell` 新增 `MacShellViewModel`。
- ViewModel 持有：
  - `RelaySnapshotPayload`
  - draft input
  - selected model
  - selected effort
  - selected permission mode
  - plan mode toggle
- `RelaySessionSnapshotPayload` 新增直接 initializer，支持 UI 修改 mock session fields。
- Session toolbar 从静态 chip 升级为：
  - model picker
  - effort picker
  - Plan toggle
  - permission mode picker
- Composer 从静态文字升级为 `TextField` + Send action。
- Approval inline 新增：
  - Approve action
  - Discard action
- Inspector 现在通过 ViewModel 读取最新 snapshot。

验证结果：

- `swift build` 通过。
- `AgentClientMacMock` 通过，mock snapshot JSON 正常。
- `RelayCoreFixtureProbe` 通过。
- 没有启动 GUI 进程；仍只做编译和非 GUI fixture 验证。

设计说明：

- 这仍是交互骨架，不是最终视觉稿。
- 当前重点是数据流和可编译结构。
- 后续真正视觉打磨需要主 Agent 继续按 Hermes Desktop / Lody 的高密度工作台方向处理。

下一步建议：

- 将 `AgentClientMacShell` 迁移为真正 Xcode macOS App target，便于截图验证和真实窗口调试。
- 或继续在 SwiftPM 中补：
  - mock session list 多条数据
  - selected inspector tab
  - diff text mock
  - approval resolved 状态
  - command event rows

#### Claude Code 辅助执行策略

时间：2026-06-21

本机状态：

- Claude Code CLI 可用。
- 命令路径：`/Applications/cmux.app/Contents/Resources/bin/claude`
- 版本：`2.1.168 (Claude Code)`
- 支持非交互调用：`claude -p "<prompt>"`
- 支持限制工具：`--tools`、`--allowedTools`、`--disallowedTools`
- 支持权限模式：`--permission-mode`
- 支持模型选择：`--model`
- 支持结构化/流式输出：`--output-format json | stream-json`
- 已验证最小调用：
  - 普通沙箱内会进入 API request 后出现 connection error 并重试。
  - 授权网络环境下 `claude -p "只输出 OK"` 成功返回 `OK`。
  - 实际模型：`deepseek-v4-flash`
  - 单次最小调用耗时约 1.6s，API 时间约 1.0s。

使用原则：

- Claude Code 可作为简单任务辅助执行者，尤其适合不依赖 Codex 额度的代码整理、文档草拟、本地静态分析、方案比较。
- 主 Agent 对 Claude Code 的交付结果负责；Claude 的输出不能直接视为最终结论。
- Claude 负责提供候选分析、草案和低风险辅助实现；主 Agent 负责审阅、取舍、落地、编译验证和写回正式文档。
- DeepSeek / Claude 不负责 UI 品味、交互质感和产品设计最终判断。
- 涉及 Hermes Desktop / Lody 参考、Mac/iPhone 信息架构、视觉密度、交互层级、移动端复杂操作体验时，由主 Agent 亲自设计和把关。
- Claude 输出中任何影响产品品味的建议，默认只作为低可信草稿，不能直接采用。
- 先安排只读或低风险任务：
  - 总结已有 Swift prototype 结构。
  - 审查 parser 边界。
  - 根据现有文档生成 checklist。
  - 设计 `SessionStateReducer` 输入/输出结构。
  - 编写不执行外部命令的纯 Swift model 草案。
- 不直接让 Claude Code 修改 Obsidian 正式文档，除非主 Agent 明确审阅和合并。
- 不让 Claude Code 执行高风险命令、删除文件、写用户目录敏感位置。
- 默认使用 `--permission-mode plan` 或限制工具的 `--tools Read,Grep` 之类模式做只读分析。
- 如果需要让 Claude Code 写代码，优先写到 `/private/tmp` prototype，由主 Agent 编译验证后再决定是否迁移。
- 调用 Claude Code 时需要使用授权网络环境；否则会卡在 firstParty API connection retry。

建议调用方式：

```bash
claude -p "<任务说明>" --permission-mode plan --output-format json
```

或用于只读代码审查：

```bash
claude -p "<任务说明>" --tools Read,Grep --permission-mode default --output-format json
```

可交接任务：

- 让 Claude Code 先审查 `/private/tmp/AgentClientCorePrototype/Sources/AgentClientCore` 的模型拆分。
- 让 Claude Code 草拟 `SessionStateReducer` 的状态机和事件映射表。
- 主 Agent 根据 Claude 输出做取舍、落地和验证。

当前分工计划：

- Claude Code：只读审查 Swift core，草拟 `SessionStateReducer` 状态模型和 notification 映射表。
- 主 Agent：判断哪些建议适合 M1，亲自实现 reducer 基础模型，运行 `swift build` / fixture probe 验证，并把结果写回本计划。

#### macOS App bundle 启动验证

时间：2026-06-21

本轮目标：

- 将当前 SwiftPM `AgentClientMacShell` 从“可执行文件”提升为可被 macOS 启动的 `.app` bundle。
- 用真实窗口验证当前 Mac shell 的布局是否能跑起来。
- 截图检查 UI 骨架，判断下一步重点。

产物：

- SwiftPM 项目：`/private/tmp/AgentClientM1Prototype`
- App bundle：`/private/tmp/AgentClientAppPrototype/AgentClient.app`
- 截图：`/private/tmp/agentclient-mac-shell.png`

执行结果：

- `swift build --product AgentClientMacShell` 通过。
- 已生成最小 app bundle：
  - `Contents/MacOS/AgentClientMacShell`
  - `Contents/Info.plist`
- `open /private/tmp/AgentClientAppPrototype/AgentClient.app` 启动成功。
- 首次 `screencapture -x` 因显示捕获失败未生成图片。
- 第二次使用 `screencapture -x -T 1 /private/tmp/agentclient-mac-shell.png` 成功。
- 截图确认 app 窗口真实显示，三栏结构和右侧 Inspector 已渲染。
- 已通过 `osascript` 退出 app，`pgrep -fl AgentClientMacShell` 确认无残留进程。

视觉检查结论：

- 当前 shell 已达到“可启动、可看见、可验证交互骨架”的阶段。
- 右侧 Inspector 信息结构可用，能展示文件、approval、session settings。
- 中央区能展示模型、effort、plan、权限、approval card、composer 等核心 session 下配置。
- 但当前视觉仍明显是工程骨架，不是最终产品界面。
- 与 Hermes Desktop / Lody 的目标品味相比，当前不足包括：
  - 左侧信息架构还不够克制和高级。
  - Toolbar 控件过于系统默认，缺少统一节奏。
  - Approval card 的层级、边距、状态表达还偏粗。
  - 中央对话区的内容密度和可扫描性不足。
  - 右侧 Inspector 需要更像工作台，不应只是静态详情面板。

下一步优先级：

1. 继续保留当前 relay/core 验证成果，不急着扩更多底层能力。
2. 进入 Mac shell 的第一轮产品化 UI：
   - 以 Hermes Desktop 为主参考，Lody 为品味参考。
   - 重新打磨三栏比例、toolbar、session header、approval 区、diff/文件区、composer。
   - 保持“工具界面”而不是“营销界面”：高密度、安静、可扫描、可长时间工作。
3. 补一个更完整的 mock snapshot：
   - 多 session。
   - 多条消息。
   - 多个 changed files。
   - diff preview。
   - approval pending / approved / discarded 状态。
4. 再做一次 app bundle 启动和截图验证。

注意：

- UI 品味和交互质感由主 Agent 亲自负责。
- Claude Code / DeepSeek 不参与最终 UI 设计决策，只能做低风险结构性辅助。

#### Mac shell UI v2 产品化骨架

时间：2026-06-21

目标：

- 把第一版 SwiftUI 默认控件原型，推进到更接近 Hermes Desktop / Lody 品味的高密度工作台骨架。
- 保留 Codex session 下的配置控制：
  - model
  - effort：low / medium / high / xhigh
  - Plan 开关
  - permission mode：Read Only / Default / Full Access
- 同时展示移动端需要接管的核心对象：
  - session list
  - conversation
  - command approval
  - changed files
  - diff preview
  - per-file approve / discard
  - session settings

代码变更：

- 替换 `/private/tmp/AgentClientM1Prototype/Sources/AgentClientMacShell/main.swift`
- 新增/调整的 UI 层：
  - `MacShellViewModel`
  - `SessionRail`
  - `ConversationPane`
  - `SessionHeader`
  - `ApprovalInline`
  - `InspectorPane`
  - `FileChangeRow`
  - `DiffPreview`
  - `AppTheme`
- mock 数据从单 session 扩展为：
  - 3 个 session
  - 多条 conversation message
  - 3 个 changed files
  - diff preview
  - command approval pending
  - file approval state：Pending / Approved / Discarded

验证：

- `swift build --product AgentClientMacShell` 通过。
- 已复制新二进制到：
  - `/private/tmp/AgentClientAppPrototype/AgentClient.app/Contents/MacOS/AgentClientMacShell`
- 已启动 app bundle 并截图：
  - `/private/tmp/agentclient-mac-shell-v2.png`
  - `/private/tmp/agentclient-mac-shell-v2-process-front.png`
  - `/private/tmp/agentclient-mac-shell-v2-complete.png`
- 已退出 app，`pgrep -fl AgentClientMacShell` 无残留进程。

视觉检查结论：

- v2 明显比 v1 更接近工作台产品，而不是简单工程 demo。
- 中央区的 session header、配置控件、消息区、approval block、composer 已经形成较清晰的操作链路。
- 右侧 Inspector 已能承载文件变更、diff preview、session settings，符合“手机端完整接手 Mac 上 Codex 操作”的信息结构。
- 左侧 session rail 因当前截图被 cmux/Codex 窗口遮挡，未能完整自动截图检查。
- 临时 `.app` bundle 的前台/窗口行为不完全标准：
  - `tell application "AgentClient" to activate` 没有稳定置前。
  - `System Events` 置前部分生效，但仍无法完全避开当前窗口。
  - 移动窗口被系统辅助访问权限拦截：`osascript` 不允许辅助访问。

当前 UI 仍需改进：

- 左栏需要完整截图后继续微调，尤其是 session row 密度、项目路径区域、配对入口。
- 右侧 Inspector 的文件路径过长时仍有截断，需要更优雅的路径折叠方式。
- Session settings 区在窄宽度下 value 右侧会接近边缘，需要更稳定的网格布局。
- Approval block 的“Mirrors iPhone approval command”是开发说明，后续正式 UI 不应出现这类解释性文案。
- 当前 palette 已比 v1 更克制，但仍要避免过度偏蓝灰；下一轮需要增加更细的层次，而不是继续加色。

下一步：

1. 先补正式 Xcode/macOS App target 或更标准的 bundle 生成方式，解决前台、窗口、截图验证不稳定问题。
2. 再做 UI v3：
   - 完整检查左栏。
   - 处理右侧路径和 settings 截断。
   - 去掉开发解释性文案。
   - 增加 diff/approval 的真实状态层级。
3. 然后把 UI shell 与 relay command model 对齐：
   - session.start
   - session.stop
   - session.settings.update
   - approval.resolve
   - diff.get
   - project.browse

#### Hermes Desktop 参考与 Mac shell UI v3 / v3.1

时间：2026-06-21

参考来源：

- GitHub：<https://github.com/fathah/hermes-desktop>
- 本地源码副本：`/private/tmp/hermes-desktop`
- 重点阅读：
  - `src/renderer/src/screens/Layout/Layout.tsx`
  - `src/renderer/src/screens/Layout/SidebarRecentSessions.tsx`
  - `src/renderer/src/screens/Layout/ActiveSessionsBar.tsx`
  - `src/renderer/src/screens/Chat/ChatInput.tsx`
  - `src/renderer/src/screens/Chat/ModelPicker.tsx`
  - `src/renderer/src/screens/Chat/ReasoningEffortPicker.tsx`
  - `src/renderer/src/screens/Chat/MessageRow.tsx`
  - `src/renderer/src/assets/main.css`
- 重点查看预览图：
  - `previews/chat.png`
  - `previews/sessions.png`
  - `previews/models.png`

Hermes 可迁移设计点：

- 左侧固定全局导航。
- Chat / Codex 下直接嵌近期 session，不把 session 切换藏进单独页面。
- 顶部 active session bar 支持多会话并行。
- 底部 composer 是核心操作区：输入、附件、模型、上下文、发送/停止都在同一个复合容器里。
- 暗色高密度工作台适合长时间 coding。
- 状态色克制：深蓝 accent、低对比 hover/active、少量 warning/success。
- 卡片只用于列表项、消息块、approval、model/session 对象，不把整个页面卡片化。

v3 代码变更：

- 替换 `/private/tmp/AgentClientM1Prototype/Sources/AgentClientMacShell/main.swift`
- 新信息架构：
  - `Sidebar`：品牌、全局导航、recent sessions、Mac/iPhone 状态。
  - `ActiveSessionsBar`：顶部 session tabs。
  - `ChatWorkspace`：session header、conversation、approval、composer。
  - `Composer`：多行输入 + attachment/mic/model/effort/Plan/permission/folder/send 工具栏。
  - `Inspector`：changed files、diff preview、session settings。
- 视觉方向：
  - 改为 Hermes-like 暗色工作台。
  - 低对比边框和深蓝 accent。
  - 消息、tool、approval 分层展示。
  - 右侧保留 session-scoped inspector。

v3.1 修正：

- 给 composer 的 `TextEditor` 增加 placeholder。
- 收紧 composer 高度，避免底部出现大块空黑面板。

验证：

- `swift build --product AgentClientMacShell` 通过。
- 已复制到：
  - `/private/tmp/AgentClientAppPrototype/AgentClient.app/Contents/MacOS/AgentClientMacShell`
- 已启动 app bundle 并截图：
  - v3：`/private/tmp/agentclient-mac-shell-v3.png`
  - v3.1：`/private/tmp/agentclient-mac-shell-v3-1.png`
- v3.1 截图完整显示左栏、顶部 active sessions、中央 conversation、底部 composer、右侧 inspector。
- 已退出 app，未留下后台进程。

v3.1 视觉检查：

- 方向正确：整体已经更接近 Hermes Desktop 的工作台密度和暗色产品感。
- 左栏结构比 v2 更清楚：全局导航和 recent sessions 分开，但在同一 rail 内。
- 顶部 active session bar 让多 session 并行的产品方向更明确。
- 底部 composer 已从普通输入框升级为 session 控制中心。
- 右侧 Inspector 与“手机端接管 Mac 上 Codex 操作”的需求匹配。

仍需修正：

- 底部 toolbar 的 model / effort / permission 下拉宽度偏紧，`Full Access` 有截断。
- Approval card 在当前窗口高度下底部接近 composer，需要给消息流底部留更稳定的安全间距。
- 右侧文件卡片里的 approve / discard 小按钮太轻，需要改成更清楚但不吵的图标按钮。
- 左栏底部设备状态可以再压缩，让 recent sessions 多显示一条。
- 当前仍是单文件 SwiftUI 原型；下一轮应拆成多个 Swift 文件，按 Hermes 的组件边界组织。

下一步：

1. UI v3.2：
   - 修 toolbar 宽度和布局。
   - 修 approval card 底部安全间距。
   - 修右侧 file action 按钮。
   - 调整 sidebar recent session 密度。
2. 工程化：
   - 将 `main.swift` 拆为 `AppShell.swift`、`Sidebar.swift`、`ChatWorkspace.swift`、`Composer.swift`、`Inspector.swift`、`Theme.swift`。
   - 再考虑正式 Xcode/macOS app target。
3. 数据对齐：
   - 把 mock UI action 对接 relay command model。

#### 低 Codex 额度执行模式

时间：2026-06-21

背景：

- 当前 Codex 额度已消耗约 96%。
- 后续工作应避免触发真实 Codex CLI / app-server turn。
- 保留本地 Swift 编译、mock UI、协议设计、Obsidian 文档、截图验证。

执行原则：

- 不主动运行真实 `codex app-server` 交互。
- 不发起真实 Codex session。
- 不做需要模型返回的功能验证。
- UI 和 relay 结构继续使用 mock snapshot / fixture。
- 仅做本地 `swift build`、`.app` bundle 启动和 screenshot。
- 简单机械任务可交给 Claude Code / DeepSeek，但主 Agent 负责审阅和最终取舍。
- UI 设计、交互品味、Hermes/Lody 风格判断仍由主 Agent 亲自负责。

低额度下可继续推进：

- Mac shell UI v3.2 / v3.3。
- SwiftUI 文件拆分。
- Relay command model 文档和 mock action 映射。
- iPhone 信息架构和交互草图文档。
- 局域网配对安全模型。
- 文件 approve / discard 语义澄清。
- 截图验证和设计基准更新。

低额度下暂停：

- 真实 Codex session start / turn start。
- 真实 approval request/response 端到端验证。
- 真实 model/list 动态读取。
- 真实 project browse / diff get 与 Codex app-server 对接。

当前下一步：

1. 在不调用 Codex 的情况下做 UI v3.2：
   - 修底部 toolbar 截断。
   - 修 approval card 与 composer 的安全间距。
   - 修右侧 file approve / discard 按钮。
   - 压缩 sidebar 底部设备状态。
2. 只运行 `swift build --product AgentClientMacShell` 做本地编译验证。
3. 如需要截图，只启动 mock `.app`，不触发真实 Codex。

#### 低额度模式下的 Mac shell UI v3.2 / v3.2.1

时间：2026-06-21

约束：

- 未调用真实 Codex CLI / app-server。
- 未发起真实 Codex session。
- 仅使用 SwiftUI mock 数据、本地 `swift build`、mock `.app` 截图验证。

v3.2 修改：

- 压缩左栏：
  - 减少全局 nav 和 recent sessions 的垂直间距。
  - 压缩底部 Mac/iPhone 设备状态区。
- 修 composer toolbar：
  - 将 toolbar spacing 从 10 收紧到 7。
  - 给 model / effort / permission menu 设置固定宽度。
  - `Full Access` 不再明显截断。
- 修消息区：
  - 给 ScrollView 内容底部增加安全距离。
- 修右侧文件操作：
  - 将小图标按钮改为 `Approve` / `Discard` 明确动作按钮。
  - 保持低对比，但比 v3.1 更可识别。

v3.2.1 修改：

- 进一步压缩垂直空间：
  - Session header 纵向 padding 从 18 降到 14。
  - 消息 spacing 从 18 降到 14。
  - composer 输入区高度从 72 降到 56。
  - composer 外层 padding 从 16 降到 12。
  - approval card 内部 spacing / padding 降低。
- 目标是让 approval card 的操作按钮在默认窗口高度下可见。

验证：

- `swift build --product AgentClientMacShell` 通过。
- 已复制到 mock app bundle：
  - `/private/tmp/AgentClientAppPrototype/AgentClient.app/Contents/MacOS/AgentClientMacShell`
- 截图：
  - v3.2：`/private/tmp/agentclient-mac-shell-v3-2.png`
  - v3.2.1：`/private/tmp/agentclient-mac-shell-v3-2-1.png`
- v3.2.1 截图确认：
  - `Full Access` 可完整显示。
  - approval card 的 `Approve` / `Discard` 可见。
  - 右侧 file row 的 `Approve` / `Discard` 更清楚。
  - 左栏 recent sessions 和底部设备状态更紧凑。
- 已退出 mock app，无需保留后台进程。

残留问题：

- 当前仍是单文件 SwiftUI prototype，下一步应拆文件。
- 当前窗口截图受桌面其他窗口影响；正式 Xcode app target 后再做更稳定截图。
- 右侧 Inspector CWD 仍会在较窄宽度下压缩，应在后续改为路径折叠组件。
- File action 现在更清楚，但在视觉上略重，后续可以做 hover/selected 状态区分。

下一步建议：

1. 不消耗 Codex 额度地拆分 SwiftUI 文件。
2. 建立 mock relay command action：
   - `session.start`
   - `session.stop`
   - `session.settings.update`
   - `approval.resolve`
   - `diff.get`
   - `project.browse`
3. 完成 iPhone 端信息架构文档。

#### 低额度模式下的 SwiftUI 文件拆分与 mock relay command

时间：2026-06-21

约束：

- 未调用真实 Codex CLI / app-server。
- 未发起真实 session / turn。
- 仅做 SwiftUI 本地拆分、mock command action、`swift build` 和 mock app 启动。

拆分前：

- `Sources/AgentClientMacShell/main.swift`
- 单文件约 989 行，包含：
  - App 入口
  - ViewModel
  - mock models
  - Sidebar
  - ChatWorkspace
  - Composer
  - Inspector
  - Components
  - Theme

拆分后：

- `Sources/AgentClientMacShell/AgentClientMacShellApp.swift`
  - `@main` App 入口。
- `Sources/AgentClientMacShell/Models.swift`
  - `MacShellViewModel`
  - `NavItem`
  - `ActiveRun`
  - `SessionListItem`
  - `ConversationMessage`
  - `ChangedFileMock`
  - `MockRelayCommandAction`
  - `MockRelayCommandType`
- `Sources/AgentClientMacShell/AppShell.swift`
  - `MacShellView`
- `Sources/AgentClientMacShell/Sidebar.swift`
  - `Sidebar`
  - `NavRow`
  - `SidebarSessionRow`
  - `ActiveSessionsBar`
  - `ActiveRunChip`
- `Sources/AgentClientMacShell/ChatWorkspace.swift`
  - `ChatWorkspace`
  - `SessionHeader`
  - `MessageRow`
  - `CommandApprovalCard`
  - `Composer`
  - `SessionMenu`
- `Sources/AgentClientMacShell/Inspector.swift`
  - `Inspector`
  - `FileRow`
  - `FileActionButton`
  - `DiffPreview`
  - `DiffLine`
  - `InspectorSection`
- `Sources/AgentClientMacShell/Components.swift`
  - reusable small UI primitives。
- `Sources/AgentClientMacShell/Theme.swift`
  - `Theme`

实现细节：

- 删除 `main.swift` 后新增 `AgentClientMacShellApp.swift`。
- 原因：多文件 SwiftPM executable 中继续使用 `main.swift` + `@main` 会触发：
  - `'main' attribute cannot be used in a module that contains top-level code`
- 改名后编译通过。

mock relay command action：

- 新增 `MockRelayCommandType`：
  - `session.start`
  - `session.turn.start`
  - `session.settings.update`
  - `approval.resolve`
  - `file.approve`
  - `file.discard`
  - `snapshot.get`
- 新增 `MockRelayCommandAction`。
- `MacShellViewModel` 新增 `commandLog`。
- UI action 会写入 command log：
  - 发送输入 -> `session.turn.start`
  - model / effort / Plan / permission 变化 -> `session.settings.update`
  - command approval approve / discard -> `approval.resolve`
  - file approve / discard -> `file.approve` / `file.discard`
- `Inspector` 新增 `Mock Commands` 区，展示最近 command log。

验证：

- 首次拆分后 `swift build --product AgentClientMacShell` 失败，原因是 `main.swift` + `@main` 冲突。
- 将入口改为 `AgentClientMacShellApp.swift` 后：
  - `swift build --product AgentClientMacShell` 通过。
- 已复制二进制到 mock app bundle：
  - `/private/tmp/AgentClientAppPrototype/AgentClient.app/Contents/MacOS/AgentClientMacShell`
- 已启动 mock app 并截图：
  - `/private/tmp/agentclient-mac-shell-split-v1.png`
- 截图受其他窗口遮挡，但 app 已成功启动并渲染。
- 已退出 app，`pgrep -fl AgentClientMacShell` 无残留进程。

下一步：

1. 继续低额度模式，做 iPhone 端信息架构文档。
2. 或补 mock relay command 的 fixture probe，验证 command log 数据结构可编码成 relay envelope。
3. 等 Codex 额度恢复后，再恢复真实 app-server 端到端验证。

#### iPhone 端信息架构文档

时间：2026-06-21

新增文档：

- `产品/AI 编程 CLI 客户端 iPhone 信息架构.md`

目标：

- 将“iPhone 是完整远程操作端，不是只读监控面板”落成可设计、可开发的信息架构。
- 在不消耗 Codex 额度的前提下，明确移动端页面、状态、操作入口、sheet、通知和 relay command 映射。

主要内容：

- 一级信息架构：
  - Sessions
  - Inbox
  - Files
  - Devices
- Sessions 首页：
  - Mac 在线状态
  - Needs Attention / Running / Recent 分组
  - New Session 流程
- Session Workspace：
  - Session Header
  - Conversation / Event Stream
  - Bottom Composer
  - Session Tools
- Inbox：
  - Command Approval
  - Plan Decision
  - File Review
  - Failure
  - Mac-only Authorization
  - Connection
- Files / Diff：
  - File List
  - Diff Viewer
  - approve / approve & stage / discard session changes / discard all file changes
- Session Settings Sheet：
  - model
  - effort
  - Plan mode
  - permission mode
  - approval policy
  - sandbox mode
  - cwd
- Project Browser：
  - 浏览 Mac 用户目录
  - 敏感目录提示
- Devices：
  - 配对、重连、吊销、Face ID / Touch ID 策略
- Notifications：
  - approval needed
  - plan ready
  - session completed / failed
  - Mac disconnected
  - Mac-only authorization needed
- Relay command 映射：
  - `session.start`
  - `session.turn.start`
  - `session.stop`
  - `session.settings.update`
  - `approval.resolve`
  - `diff.get`
  - `file.approve`
  - `file.stage`
  - `file.discardSessionChanges`
  - `file.discardAllChanges`
  - `project.browse`
  - `replay.from`
  - `snapshot.get`

关键设计判断：

- iPhone 首页默认是 session priority dashboard，而不是 chat landing page。
- 待处理事项必须聚合到 Inbox，同时也要嵌入对应 Session Workspace。
- Diff review 是移动端核心能力，应有固定底部 action bar。
- Session 配置是当前 session / turn 上下文，不是全局设置。
- 高风险操作使用 iPhone 本机生物识别，而不是要求 Mac 二次确认。

下一步：

1. 在低额度模式下做 iPhone SwiftUI mock：
   - Sessions Home
   - Session Workspace
   - Inbox
   - Diff Viewer
   - Session Settings Sheet
2. 或先补 relay command fixture probe，验证这些 command 可编码为 relay envelope。

#### Claude Code 辅助与 relay command fixture probe

时间：2026-06-21

低额度策略：

- 主 Agent 继续负责架构判断、代码修改、验证和文档落地。
- Claude Code 作为只读辅助，负责抽取 relay command checklist。
- Claude 未写文件，未参与 UI 设计取舍。
- Claude 输出只作为对照清单，最终实现由主 Agent 审阅和修正。

Claude Code 辅助输出的有用检查点：

- `session.start` 应包含 cwd、model、effort、permission/sandbox/approval、planMode、initialPrompt。
- `session.turn.start` 应支持 turn 级 model/effort/approval/sandbox 覆盖。
- `approval.resolve` 要处理 Mac/iPhone 双端同时响应的竞态。
- `diff.get` 应以 app-server diff 优先，Git diff fallback。
- `project.browse` 需要敏感目录提示和权限错误。
- `replay.from` 应以 `lastSeenSeq` / `afterSeq` 触发增量重放。
- `snapshot.get` 应有独立 payload，不应复用 replay payload。
- file discard 需要区分 session changes 与 all changes，并考虑 baseline/conflict。

代码变更：

- 更新 `Package.swift`：
  - 新增 product：`RelayCommandFixtureProbe`
  - 新增 target：`RelayCommandFixtureProbe`
- 更新 `Sources/AgentClientCore/RelayProtocol.swift`：
  - `RelayCommandType` 新增：
    - `file.approve`
    - `file.stage`
    - `file.discardSessionChanges`
    - `file.discardAllChanges`
  - 新增 command payload：
    - `RelaySessionStartCommandPayload`
    - `RelayTurnStartCommandPayload`
    - `RelaySessionStopCommandPayload`
    - `RelaySettingsUpdateCommandPayload`
    - `RelayApprovalResolveCommandPayload`
    - `RelayDiffGetCommandPayload`
    - `RelayProjectBrowseCommandPayload`
    - `RelayFileCommandPayload`
    - `RelaySnapshotGetCommandPayload`
- 新增：
  - `Sources/RelayCommandFixtureProbe/main.swift`

验证覆盖：

- `session.start`
- `session.turn.start`
- `session.stop`
- `session.settings.update`
- `approval.resolve`
- `diff.get`
- `project.browse`
- `file.approve`
- `file.stage`
- `file.discardSessionChanges`
- `file.discardAllChanges`
- `replay.from`
- `snapshot.get`

验证结果：

- `swift build --product RelayCommandFixtureProbe` 通过。
- `swift build --product AgentClientMacShell` 通过。
- `.build/debug/RelayCommandFixtureProbe` 通过。
- 输出：

```text
RelayCommandFixtureProbe passed: session.start, session.turn.start, session.stop, session.settings.update, approval.resolve, diff.get, project.browse, file.approve, file.stage, file.discardSessionChanges, file.discardAllChanges, replay.from, snapshot.get
```

设计修正：

- 初版 fixture 曾临时用 `RelayReplayRequestPayload` 表示 `snapshot.get`。
- 根据协议语义和 Claude checklist 对照，已修正为独立 `RelaySnapshotGetCommandPayload`。

下一步：

1. 在 Mac mock UI 的 command log 中改用 core 的 `RelayCommandType` / payload，而不是本地 mock enum。
2. 做 iPhone SwiftUI mock：
   - Sessions Home
   - Session Workspace
   - Inbox
   - Diff Viewer
   - Session Settings Sheet
3. 后续额度恢复后，把 fixture payload 映射到真实 Mac Relay command handler。

#### Mac mock UI command log 收敛到 core RelayCommandType

时间：2026-06-21

目标：

- 去掉 Mac shell mock UI 中的本地 `MockRelayCommandType`。
- 让 UI command log 直接使用 `AgentClientCore.RelayCommandType`。
- 避免 UI mock 和 relay core 协议继续分叉。

代码变更：

- 更新：
  - `/private/tmp/AgentClientM1Prototype/Sources/AgentClientMacShell/Models.swift`
- 删除本地 enum：
  - `MockRelayCommandType`
- 重命名：
  - `MockRelayCommandAction` -> `RelayCommandLogEntry`
- `RelayCommandLogEntry.type` 改为：
  - `RelayCommandType`
- `MacShellViewModel.record(...)` 改为接收：
  - `RelayCommandType`
- 文件 discard 的 mock command 从泛化的 `file.discard` 改为正式协议里的：
  - `file.discardSessionChanges`

验证：

- `swift build --product AgentClientMacShell` 通过。
- `swift build --product RelayCommandFixtureProbe` 通过。
- `.build/debug/RelayCommandFixtureProbe` 通过。

验证输出：

```text
RelayCommandFixtureProbe passed: session.start, session.turn.start, session.stop, session.settings.update, approval.resolve, diff.get, project.browse, file.approve, file.stage, file.discardSessionChanges, file.discardAllChanges, replay.from, snapshot.get
```

状态：

- Mac mock UI 和 core relay command type 已初步收敛。
- 下一步如果继续做 UI action，应优先生成 core payload，而不是只生成字符串 detail。

#### Mac shell 接入 Codex app-server runtime 骨架

时间：2026-06-21

目标：

- 开始从纯 mock UI 走向真实 Codex CLI 控制。
- 在低额度状态下，只接入 CLI 探测、app-server 生命周期、`initialize`、`model/list` 等非 turn 能力。
- 不自动发送 `turn/start`，避免误消耗 Codex 额度。

Claude Code 辅助：

- 已安排 Claude Code 做只读审查。
- 它给出的主线是：`CodexAppServerClient -> SessionStateReducer -> MacShellViewModel -> SwiftUI`。
- 它的输出中有部分旧方法名和过度激进建议，例如自动启动真实 session/turn，本轮没有采纳。
- 采纳的部分是：把 ViewModel 作为桥接点，按 lifecycle、initialize、model/list、approval、diff 的顺序逐步接入。

代码变更：

- 新增：
  - `/private/tmp/AgentClientM1Prototype/Sources/AgentClientCore/CodexCLIDetector.swift`
  - `/private/tmp/AgentClientM1Prototype/Sources/AgentClientMacShell/CodexRuntimeBridge.swift`
- 更新：
  - `/private/tmp/AgentClientM1Prototype/Sources/AgentClientMacShell/Models.swift`
  - `/private/tmp/AgentClientM1Prototype/Sources/AgentClientMacShell/ChatWorkspace.swift`
  - `/private/tmp/AgentClientM1Prototype/Sources/AgentClientMacShell/Inspector.swift`

新增能力：

- `CodexCLIDetector`：
  - 查找 `~/.npm-global/bin/codex`
  - 查找 `/opt/homebrew/bin/codex`
  - 查找 `/usr/local/bin/codex`
  - 回退扫描 `PATH`
  - 读取 `codex --version`
- `CodexRuntimeBridge`：
  - 管理 `CodexAppServerClient`
  - 手动启动 / 停止 app-server
  - 发送 `initialize`
  - 发送 `model/list`
  - 预留 `thread/start`
  - 预留 `turn/start`
  - 处理 approval response
  - 把 app-server event 输入 `SessionStateReducer`
- Mac Shell UI：
  - Inspector 新增 `Codex Runtime` 区块。
  - 支持手动 `Detect`。
  - 支持手动 `Init`，执行 app-server `initialize + model/list`，不发送 turn。
  - 支持手动 `Stop`。
  - Composer model menu 优先使用真实 `model/list` 返回结果；没有真实结果时使用 fallback model。

验证：

- `swift build --product AgentClientMacShell` 通过。
- `swift build --product CodexDetectorProbe` 通过。
- `.build/debug/CodexDetectorProbe` 通过。

验证输出：

```text
installed=true
path=~/.npm-global/bin/codex
version=codex-cli 0.141.0
```

补充修复：

- SwiftUI/GUI 进程中启动 `codex --version` 时，曾出现：

```text
env: node: No such file or directory
```

- 原因：Codex CLI 入口是 `#!/usr/bin/env node`，GUI/Swift 子进程环境里的 `PATH` 不稳定，找不到 `/usr/local/bin/node`。
- 已在 core 层补齐 Codex 子进程环境：
  - `~/.npm-global/bin`
  - `/usr/local/bin`
  - `/opt/homebrew/bin`
  - `/usr/bin`
  - `/bin`
  - `/usr/sbin`
  - `/sbin`
- `CodexCLIDetector` 和 `CodexAppServerClient` 现在共用同一套 `codexProcessEnvironment()`。

当前限制：

- 还没有把 `sendDraft()` 接到真实 `turn/start`。
- 还没有把真实 reducer snapshot 映射回完整聊天消息和文件列表。
- 还没有跑真实 app-server `Init` 按钮截图验证。
- 还没有做 iPhone 端真实 RelayClient。
- `/private/tmp/AgentClientAppPrototype/AgentClient.app` bundle 仍存在启动即退出 / 窗口不可稳定激活问题。
- 最新 debug 可执行文件可以启动进程，但本轮最后一次验证中窗口没有稳定出现在前台；需要优先修 SwiftUI app lifecycle / bundle 包装。

下一步：

1. 先修 app bundle / SwiftUI lifecycle：
   - `open /private/tmp/AgentClientAppPrototype/AgentClient.app` 后必须稳定显示主窗口。
   - 菜单栏显示名、进程名、bundle executable 必须一致，避免 AppleScript 激活失败。
2. 启动 Mac shell，手动点击 Inspector 里的 `Detect` 和 `Init`，验证 Codex app-server 能返回 `initialize` / `model/list`。
3. 如果 `model/list` 正常，把真实 model options 固化到 session toolbar。
4. 实现 `thread/start`，但仍不自动 `turn/start`。
5. 实现 `sendDraft()` 的真实 `turn/start` 分支，默认保留 mock/real 开关。
6. 把 reducer snapshot 映射到：
   - `messages`
   - `pendingApproval`
   - `files`
   - `snapshot.connection`
7. 真实跑一个低风险只读 prompt，验证输出流、approval、diff 状态。

#### Bundle/lifecycle 修复与真实 Codex app-server 验证

时间：2026-06-21

目标：

- 让 `/private/tmp/AgentClientAppPrototype/AgentClient.app` 可以通过 `open` 稳定启动。
- 用真实 Codex CLI 验证 app-server 链路，而不只停留在 mock。

问题定位：

- app bundle 初期 `open` 后启动即退出。
- 最新 crash 报告显示崩溃发生在 SwiftUI / AttributeGraph 初始化期间。
- 根因不是 UI 布局，而是 `CodexRuntimeBridge` 在 `@StateObject` 初始化阶段同步执行 `codex --version`。
- `Process.waitUntilExit()` 在 SwiftUI view graph 构建期间触发 AppKit / CFRunLoop 重入，导致 AttributeGraph precondition abort。

修复：

- `CodexRuntimeBridge` 初始化阶段不再跑 `codex --version`。
- `CodexCLIDetector.detect(...)` 新增 `includeVersion` 参数。
- 初始化阶段只做轻量 CLI 路径探测：
  - `CodexCLIDetector.detect(includeVersion: false)`
- 点击 `Detect` 时再用 `Task.detached` 后台执行完整版本探测。
- app bundle 补全 `Info.plist`：
  - `CFBundleDisplayName`
  - `CFBundleSupportedPlatforms`
  - `LSApplicationCategoryType`
  - `NSPrincipalClass`
- 每次更新 bundle 后执行：
  - `xattr -cr /private/tmp/AgentClientAppPrototype/AgentClient.app`
  - `codesign --force --deep --sign - /private/tmp/AgentClientAppPrototype/AgentClient.app`

代码变更：

- 更新：
  - `/private/tmp/AgentClientM1Prototype/Sources/AgentClientCore/CodexCLIDetector.swift`
  - `/private/tmp/AgentClientM1Prototype/Sources/AgentClientCore/CodexAppServerClient.swift`
  - `/private/tmp/AgentClientM1Prototype/Sources/AgentClientCore/SessionStateReducer.swift`
  - `/private/tmp/AgentClientM1Prototype/Sources/AgentClientMacShell/CodexRuntimeBridge.swift`
  - `/private/tmp/AgentClientM1Prototype/Sources/AgentClientMacShell/Models.swift`
  - `/private/tmp/AgentClientAppPrototype/AgentClient.app/Contents/Info.plist`
- 新增：
  - `/private/tmp/AgentClientM1Prototype/Sources/CodexDetectorProbe/main.swift`
  - `/private/tmp/AgentClientM1Prototype/Sources/CodexAppServerInitProbe/main.swift`

真实 app-server 验证：

- `CodexAppServerInitProbe` 使用当前 Swift core 的 `CodexAppServerClient` 启动真实：
  - `codex app-server --stdio`
- 发送：
  - `initialize`
  - `initialized` notification
  - `model/list`
- 验证通过。

真实验证输出：

```text
codex=~/.npm-global/bin/codex
version=codex-cli 0.141.0
response id=1 method=initialize keys=["codexHome", "platformFamily", "platformOs", "userAgent"]
notification method=remoteControl/status/changed
response id=2 method=model/list keys=["data", "nextCursor"]
models.prefix=gpt-5.5, gpt-5.4, gpt-5.4-mini
CodexAppServerInitProbe passed
```

真实 read-only turn 验证：

- 使用已有 Node probe 跑真实只读 turn。
- 配置：
  - model：`gpt-5.5`
  - effort：`low`
  - sandbox：`readOnly`
  - approvalPolicy：`on-request`
  - prompt：只要求回复一句话，不编辑文件。
- 验证通过：
  - `thread/start`
  - `thread/started`
  - `thread/settings/updated`
  - `turn/start`
  - `turn/started`
  - `item/agentMessage/delta`
  - `thread/tokenUsage/updated`
  - `account/rateLimits/updated`
  - `turn/completed`

真实 turn 输出：

```text
The Codex app-server read-only turn is working.
```

额外适配：

- `model/list` 真实结果字段是 `data`，不是只使用 `models`。
- `CodexRuntimeBridge.updateModels` 已支持：
  - `data[].model`
  - `data[].slug`
  - `models[]`
- `thread/started` 真实通知是扁平结构：
  - `id`
  - `sessionId`
  - `cwd`
  - `status`
- `SessionStateReducer.threadStarted` 已支持扁平结构和旧的 `thread` 嵌套结构。

验证命令：

- `swift build --product AgentClientMacShell` 通过。
- `swift build --product CodexAppServerInitProbe` 通过。
- `swift build --product RelayCoreFixtureProbe` 通过。
- `.build/debug/RelayCoreFixtureProbe` 通过。
- `.build/debug/CodexAppServerInitProbe /private/tmp/AgentClientM1Prototype` 通过。
- `open /private/tmp/AgentClientAppPrototype/AgentClient.app` 后进程保活。

下一步：

1. 把 Mac UI 的 `Init` 按钮和真实 app-server 状态做完整联动：
   - 点击 `Init` 后显示 `gpt-5.5 / gpt-5.4 / gpt-5.4-mini`。
   - 显示 app-server online/offline 状态。
2. 在 Mac UI 中增加 mock/real 模式开关。
3. 将 `sendDraft()` 接到真实 `thread/start + turn/start`，默认 read-only。
4. 把真实 `item/agentMessage/delta` 映射到 `messages`。
5. 把真实 `thread/settings/updated` 映射到 session toolbar。
6. 把真实 `account/rateLimits/updated` 显示到 inspector。

#### Claude Code 协作边界验证

时间：2026-06-21

结论：

- Claude Code 可以直接写代码，但必须给小颗粒、边界清楚的任务。
- 不适合一次性派发“完整 runtime 接线 + UI 联动 + sendDraft real mode”这种大任务。
- 第一次大任务从 Obsidian 目录启动，Claude 的读写权限没有落到 `/private/tmp/AgentClientM1Prototype`，大量 Read/Edit 被拒，并且耗时过长，已中断。
- 第二次从 SwiftPM 项目根目录启动，只派发 `CodexRuntimeBridge` 小任务，成功完成并通过 build。

Claude Code 已完成：

- 在 `Sources/AgentClientMacShell/CodexRuntimeBridge.swift` 新增：
  - `rateLimitText`
  - `onEventReceived`
  - 每个 `CodexAppServerEvent` 的外部回调入口
  - `account/rateLimits/updated` 的基础处理

人工把关修正：

- Claude 初版按顶层 `plus / usedPercent / window` 解析 rate limit。
- 真实 app-server 输出是：
  - `params.rateLimits.planType`
  - `params.rateLimits.primary.usedPercent`
  - `params.rateLimits.primary.windowDurationMins`
  - `params.rateLimits.primary.resetsAt`
- 已修正 `formatRateLimits(...)`，现在输出：

```text
Plan: plus | Used: 85% | Window: 300m | Reset: <timestamp>
```

验证：

- `swift build --product AgentClientMacShell` 通过。
- 最新二进制已同步到：
  - `/private/tmp/AgentClientAppPrototype/AgentClient.app/Contents/MacOS/AgentClientMacShell`
- bundle 已重新执行：
  - `xattr -cr`
  - `codesign --force --deep --sign -`

后续 Claude Code 使用策略：

- 可以让 Claude 做：
  - 单文件或少量文件的协议字段适配。
  - reducer/action 映射。
  - fixture/probe。
  - 非 UI 的 ViewModel 状态管线。
- 不让 Claude 做：
  - UI 视觉重设计。
  - Hermes/Lody 风格判断。
  - 大范围架构改动。
  - 真实 turn 消耗验证。

下一次适合派给 Claude 的任务：

- 为 `CodexRuntimeBridge` 增加 pending request registry：
  - 记录 `initialize`
  - 记录 `model/list`
  - 记录 `thread/start`
  - 记录 `turn/start`
  - 让 ViewModel 能判断 response 属于哪个请求。

#### Runtime bridge 接线收尾：pending registry、mock/real 模式、approval 实模统一

时间：2026-06-21

本轮任务：接手之前 Claude/DeepSeek 已实现的 CodexRuntimeBridge + MacShellViewModel 接线，修复 4 个剩余问题。

已完成的继承工作（前序 session 已实现）：

- `CodexRuntimeBridge` 中 `PendingRequestKind` enum 和 `pendingRequests` registry 已存在。
- `MacShellViewModel` 中 `RuntimeMode` enum + `sendDraft()` mock/real 分发已存在。
- real 模式 `sendDraft` → `enqueueDraft` → initialize → model/list → thread/start → turn/start 异步链已完成。
- `handleSnapshotUpdate` → `agentMessage/delta` → messages streaming 映射已完成。
- Inspector 中 settings / rateLimit 展示已完成。

本轮修复：

1. 修复 `runtimeMode` 默认值从 `.real` → `.mock`。
   - 原因：用户明确要求"默认 mock"。
2. 修复 `sandboxPolicyValue` 映射错误：
   - `Full Access`：原 `"writeable"` → `"dangerFullAccess"`
   - `Default`：原 `"readOnly"` → `"workspaceWrite"`
   - `Read Only` 保持不变 `"readOnly"`
   - 原因：对齐 Codex app-server schema 实际 sandbox type 枚举值。
3. 修复 `pendingApproval` 只工作在 mock 模式的限制：
   - real 模式下现在从 `runtime.snapshot.pendingApprovals` 读取真实 pending approval。
4. 修复 `approveCommand` / `discardCommand` 在 real 模式下不调用 `runtime.resolveApproval` 的 gap：
   - real 模式现在通过 `runtime.resolveApproval(requestID:decision:)` 回写 JSON-RPC response 给 app-server。
   - mock 模式保留原有 `commandApprovalVisible = false` + log 行为。

验证：

- `swift build` 全量通过，0 warning。
- `RelayCoreFixtureProbe` 通过。
- `RelayCommandFixtureProbe` 通过。
- `AgentClientMacMock` 通过。
- App bundle 已更新并重新签名。

当前状态总结：

| 能力 | 状态 |
|---|---|
| Pending request registry | ✅ `PendingRequestKind` + `pendingRequests` dict + response 分发 |
| Mock/real 模式开关 | ✅ `RuntimeMode` enum，默认 `.mock`，composer toolbar 中有切换菜单 |
| sendDraft real 模式 | ✅ `enqueueDraft` → initialize → model/list → thread/start → turn/start |
| agentMessage/delta → messages | ✅ `handleSnapshotUpdate` 流式更新 `streamingMessageID` 占位消息 |
| thread/settings/updated → Inspector | ✅ Inspector Session 区在 real 模式下展示 runtime.snapshot.settings |
| account/rateLimits/updated → Inspector | ✅ Inspector Codex Runtime 区展示 `formatRateLimits` 输出 |
| Approval 实模统一 | ✅ real 模式从 runtime.snapshot 读 approval，resolve 回调 app-server |

低额度下可继续推进：

- 改善 real 模式下消息流的展示方式，例如 tool/command event 折叠、token usage inline。
- 把 session 状态（running/streaming/waitingApproval 等）实时反映到 UI pill。
- 丰富 Inspector Files 区在 real 模式下从 runtime.snapshot.fileChanges 读取真实文件变更。
- 补 `thread/settings/update` 的真实触发路径（当前 settings 变更只在 sendDraft 时通过 turn params 带过去，不是在 session 中热切换）。

需要 Codex 额度恢复后才能验证：

- 真实 sendDraft 端到端：user input → assistant delta streaming → turn completed → 消息区完整展示。
- 真实 approval request 触发和 UI 响应。
- 真实 fileChange / turn diff 的 Inspector 映射。

#### Sandbox 格式调试与 binary 部署问题（2026-06-21 晚间）

本轮目标：在 GUI 中跑通 real 模式 sendDraft 的完整链路（initialize → model/list → thread/start → turn/start → assistant delta streaming → 消息区展示）。

**结论：未通过。sandbox 字段格式问题仍未解决，暂停继续改动。**

##### 问题 1：sandbox 字段在 thread/start 和 turn/start 中格式不同

通过 app-server 返回的错误消息逐步推断出：

- `thread/start` 的 `sandbox` 字段（string）期望 **camelCase**：
  - `readOnly`, `workspaceWrite`, `dangerFullAccess`
- `turn/start` 的 `sandboxPolicy.type` 字段（string）期望 **kebab-case**：
  - `read-only`, `workspace-write`, `danger-full-access`

两个端点对同一概念的编码不一致。

**解决**：在 `MacShellViewModel` 中拆为两个计算属性 `threadSandboxValue`（camelCase）和 `turnSandboxValue`（kebab-case），`CodexRuntimeBridge.DraftParams` 分别存储两个值，`startThread(draft:)` 使用 `threadSandbox`，`firePendingTurn` / `startTurnFromDraft` 使用 `turnSandbox`。

##### 问题 2：binary 部署静默失败

多次修改后用户报告"同样的错误"，最终发现 `cp` 命令在目标文件正在被运行时**静默失败**（不覆盖已在内存中的二进制）。

证据：
- 编译出的二进制：2,710,976 bytes
- app bundle 中的二进制：2,710,496 bytes（旧版本）
- MD5 不匹配

**解决**：改为 `rm -f` 目标文件后再 `cp`，并显式验证 MD5。后续每次部署都校验 `md5 -q` 一致。

后续部署脚本模式：
```bash
pkill -9 -f AgentClientMacShell
pkill -9 -f "codex app-server"
sleep 2
rm -f <bundle>/AgentClientMacShell
cp <build>/AgentClientMacShell <bundle>/AgentClientMacShell
# verify MD5 match
xattr -cr <bundle> && codesign --force --deep --sign - <bundle>
```

##### 问题 3：Init 按钮竞态

`requestRuntimeInitializeAndModels()` 检查 `isInitialized` 来决定是否跳过，但 `isInitialized` 只在 `model/list` 响应返回后才设为 true。用户快速连点 Init 时，每次点击都发送新的 `initialize` 请求，导致 app-server 返回 error（"already initialized"）。

**解决**：新增 `isInitializing` 标志位，在 `initialize()` 发送时设为 true，在 `model/list` 响应成功或 error 时清除。ViewModel 的 guard 同时检查 `isInitialized || isInitializing`。

##### 问题 4：error 响应不更新 UI

当 JSON-RPC response 带 error 时，`CodexRuntimeBridge.handleResponse` 只更新 `statusText`，不更新 `snapshot`。导致 ViewModel 的 `handleSnapshotUpdate` 无法感知错误，`"…"` 占位消息永远不会被替换为错误信息。

**解决**：
- Bridge 的 error 分支现在将 error 通过 `reducer.reduce(&snapshot, .error(...))` 写入 snapshot
- ViewModel 的 `handleSnapshotUpdate` 将 streaming placeholder 替换为 `Error: <message>`，而不是追加新消息

##### 问题 5：状态文字不可见

Inspector 中的 statusText 因为 VStack 布局问题，在窗口高度不足时被遮挡在底部。

**解决**：在 ChatWorkspace 中央区（ScrollView 与 Composer 之间）新增 status bar，real 模式下显示绿点 + `runtime.statusText`，始终可见。

##### 其他改动

- `approveCommand()` / `discardCommand()` 在 real 模式下调用 `runtime.resolveApproval(requestID:decision:)` 回写 JSON-RPC response
- `pendingApproval` 计算属性支持 real 模式，从 `runtime.snapshot.pendingApprovals` 读取
- 所有改动 `swift build` 通过，0 warning；fixture probe 全部通过

##### 未解决：sandbox 错误仍然出现

尽管：
1. 确认 MD5 一致，binary 已正确部署
2. `threadSandboxValue` 返回 `"readOnly"`（camelCase）
3. `turnSandboxValue` 返回 `"read-only"`（kebabCase）
4. DraftParams 正确存储两个值，startThread/draft 用 threadSandbox，firePendingTurn/startTurnFromDraft 用 turnSandbox

用户仍然报告 sandbox 错误。最后一次错误：
```
Error: [] Invalid request: unknown variant 'read-only', expected one of 'dangerFullAccess', 'readOnly', 'externalSandbox', 'workspaceWrite'
```

这表示某个端点收到了 `read-only`（kebab-case）但期望 camelCase。从期望值列表判断，这是 `thread/start` 的 sandbox 字段。

**但代码明确使用 `draft.threadSandbox`（camelCase）来调用 `startThread(sandbox:)`。为什么 thread/start 收到了 kebab-case？**

可能原因（未验证）：
1. 还有另一条调用路径用错了 sandbox 值
2. `enqueueDraft` 中 `startThread(draft:)` 的参数映射有问题
3. draft 的 `threadSandbox` 被某个中间环节覆盖成了 kebab-case
4. JSON-RPC writer 序列化时发生了意外转换

**暂停原因**：继续盲改风险高，sandbox 格式问题需要在对 app-server schema 有更准确理解后再处理。建议：
1. 用 Node 探针独立验证 thread/start 和 turn/start 分别接受什么 sandbox 格式
2. 确认 app-server 版本 0.141.0 的实际 schema 行为
3. 或者等 Codex 额度恢复后用 CLI probe 做精确测试

##### 当前代码状态

`Models.swift`:
- `runtimeMode` 默认 `.mock`
- `threadSandboxValue`: camelCase（`readOnly` / `workspaceWrite` / `dangerFullAccess`）
- `turnSandboxValue`: kebab-case（`read-only` / `workspace-write` / `danger-full-access`）
- Init guard: `isInitialized || isInitializing` 检查
- sendDraftReal: 将两个 sandbox 值分别传入 `enqueueDraft`

`CodexRuntimeBridge.swift`:
- `isInitializing` 标志位：initialize 发送时置 true，model/list 响应或 error 时清
- `DraftParams`: 同时持有 `threadSandbox` 和 `turnSandbox`
- `startThread(draft:)`: 使用 `draft.threadSandbox`
- `firePendingTurn` / `startTurnFromDraft`: 使用 `draft.turnSandbox`
- error 响应将错误写入 snapshot.lastError
- `statusText` 含 `[build:2]` 标记用于确认二进制版本
- `startThread` / `startTurn` 的 statusText 包含 sandbox 值用于诊断

`ChatWorkspace.swift`:
- ScrollView 与 Composer 之间 real 模式下新增 status bar

`Inspector.swift`:
- 无改动（原已有 settings / rateLimit 展示）

#### Real mode schema 修复、消息流修复与 Relay 骨架推进

时间：2026-06-22

本轮目标：

- 继续把 Mac shell 从 mock UI 推进到真实 Codex app-server 可用链路。
- 修复 real mode 发送消息、连续对话、settings update、文件变更展示等问题。
- 开始沉淀 Mac Relay 本地状态层，为后续 iPhone / WebSocket 接入做准备。

##### 1. Codex app-server sandbox schema 已实测确认

前序文档中 sandbox 字段一度判断错误。本轮通过真实 app-server probe 明确了 Codex CLI `0.141.0` 的实际 schema：

- `thread/start.sandbox` 需要 **kebab-case**：
  - `read-only`
  - `workspace-write`
  - `danger-full-access`
- `turn/start.sandboxPolicy.type` 需要 **camelCase**：
  - `readOnly`
  - `workspaceWrite`
  - `dangerFullAccess`
- `thread/settings/update.sandboxPolicy.type` 也需要 **camelCase**。
- `thread/settings/update` 必须带 `threadId`。

已新增 / 使用的 probe：

- `ThreadStartSchemaProbe`
  - 真实验证 `thread/start sandbox=read-only` 成功。
  - 真实验证 `thread/start sandbox=readOnly` 失败，错误为 expected `read-only` / `workspace-write` / `danger-full-access`。
- `TurnStartSchemaProbe`
  - 真实验证 `thread/start=read-only` + `turn/start sandboxPolicy.type=readOnly` 成功。
- `SettingsUpdateSchemaProbe`
  - 离线验证 `thread/settings/update` payload shape。
- `SettingsUpdateLiveProbe`
  - 真实验证 `thread/settings/update` 带 `threadId` 后成功。

当前修正：

- `Models.swift`
  - `threadSandboxValue` 输出 kebab-case。
  - `turnSandboxValue` 输出 camelCase。
- `CodexRuntimeBridge.swift`
  - `DraftParams` 保留 `threadSandbox` 与 `turnSandbox` 两套值。
  - `thread/start` 使用 `threadSandbox`。
  - `turn/start` 使用 `turnSandbox`。
  - `thread/settings/update` 新增 `threadId`。

##### 2. Real mode 连续消息“晚一轮 / 复读上一轮回复”问题已修复

用户反馈：

- 第一条消息能收到回复。
- 发送第二条消息时，第二条气泡显示的是上一条回复。
- 看起来像“回复晚一轮”。

排查结论：

- 真实 `codex app-server` 事件流没有晚一轮。
- `TurnEventTraceProbe` 证明同一轮 turn 内会收到：
  - `item/agentMessage/delta`
  - `item/completed` agentMessage
  - `turn/completed`
- 问题在 Mac UI 的 streaming placeholder 绑定：
  - 发送第二条时，`streamingMessageID` 已指向新占位气泡。
  - 但 `runtime.snapshot.activeTurn` 仍短暂保留上一轮 completed turn。
  - `handleSnapshotUpdate` 没校验 turn id，导致上一轮 `assistantText` 写进新气泡。

已修复：

- `CodexRuntimeBridge`
  - 新增 `latestTurnID`。
  - 每次新 draft 前清空旧 `activeTurn` 和 `latestTurnID`。
  - 从 `turn/start` response 和 `turn/started` notification 提取新 turn id。
  - reducer 更新改为 copy-reduce-assign，避免 `@Published` struct 原地修改导致 UI 发布不稳定。
- `MacShellViewModel`
  - 新增 `streamingTurnID`。
  - 只有 `activeTurn.id == latestTurnID / streamingTurnID` 时才允许更新当前 placeholder。
  - 消息替换改为整数组赋值，避免 SwiftUI 对数组元素原地替换刷新不稳定。
  - `ChatWorkspace` 新增 `ScrollViewReader`，消息 id 或文本变化时自动滚到底。

##### 3. `thread/settings/update` 热切换已接通

目标：

- 当前 session 中切换 model / effort / permission 时，不只等下一次 turn params 生效，而是走真实 `thread/settings/update`。

已完成：

- `CodexRuntimeBridge.updateSettings(...)`
  - 发送 `thread/settings/update`。
  - payload 包含：
    - `threadId`
    - `model`
    - `effort`
    - `approvalPolicy`
    - `sandboxPolicy: { type: ... }`
- `MacShellViewModel.recordSettingsUpdate()`
  - mock 模式保持原记录行为。
  - real 模式在 `isInitialized && currentThreadID != nil` 时发送真实 settings update。

真实验证：

```text
response id=4 method=thread/settings/update keys=[]
SettingsUpdateLiveProbe passed
```

##### 4. Inspector Files 已接真实 fileChanges

目标：

- real mode 下右侧 Inspector 的 Changed Files 不再显示 mock 文件，而是读取 `runtime.snapshot.fileChanges`。

已完成：

- `MacShellViewModel.displayFiles`
  - mock 模式返回原 mock files。
  - real 模式从 `runtime.snapshot.fileChanges` 映射为 UI 文件项。
- `MacShellViewModel.selectedDisplayFile`
  - 支持 real 空态，避免数组越界。
- `Inspector.swift`
  - Changed Files 改用 `displayFiles`。
  - real mode 没有文件变更时显示：
    - `No file changes in this session`
  - Diff Preview 无文件时显示：
    - `No diff available`

##### 5. MacRelayService 本地状态层已建立

目标：

- 把 `CodexRuntimeBridge -> SessionStateReducer -> EventStore -> RelayProtocol` 串成一个可复用的本地 relay service。
- 先作为旁路状态层，不改变当前 Mac UI 主数据源。

新增：

- `AgentClientCore/MacRelayService.swift`
  - `ingest(_ event: CodexAppServerEvent)`
  - 内部使用 `SessionStateReducer` 更新 `SessionSnapshot`
  - 通过 `RelaySequence` 分配 seq
  - 写入 `EventStore`
  - 暴露：
    - `snapshotEnvelope(...)`
    - `replay(afterSeq:maxEvents:)`
    - `dispatch(commandType:replayRequest:correlationID:)`
    - `reset()`

当前 command dispatcher 支持：

- `snapshot.get`
- `replay.from`

其他 command 先返回 structured unsupported，后续逐个接真实 bridge。

新增验证：

- `MacRelayServiceFixtureProbe`
  - 模拟：
    - `thread/started`
    - `thread/settings/updated`
    - `turn/started`
    - `item/agentMessage/delta`
    - approval request
    - `turn/diff/updated`
    - fileChange
    - `turn/completed`
  - 验证 snapshot / seq / replay / command dispatch。

验证结果：

```text
MacRelayServiceFixtureProbe passed seq=9 events=9
```

##### 6. Mac UI 已旁路接入 MacRelayService

已完成：

- `MacShellViewModel`
  - 持有 `relayService`。
  - 订阅 `runtime.onEventReceived`。
  - 每个真实 `CodexAppServerEvent` 旁路喂给 `relayService.ingest(...)`。
  - 新增：
    - `relaySnapshot`
    - `relayEventCount`
    - `relayStatusText`
    - `requestRelaySnapshot()`
- `Inspector.swift`
  - 新增 `Mac Relay` 区块。
  - 展示：
    - relay seq
    - event count
    - active session
    - relay snapshot status
    - pending approval 数
  - `Snapshot` 按钮走本地 `snapshot.get`。

这一阶段不改变聊天 UI 的主数据源，只验证真实事件能同步进入 relay 状态层。

##### 7. 本地 HTTP Relay server skeleton 已完成

目标：

- 在正式 WebSocket 前，先验证 relay 状态可以通过本地网络接口暴露给模拟客户端。

新增：

- `AgentClientCore/MacRelayHTTPServer.swift`
  - 基于 `Network` 的 loopback HTTP server。
  - 当前支持：
    - `GET /snapshot`
    - `GET /replay?afterSeq=...&maxEvents=...`
  - 返回：
    - `RelayEnvelope<RelaySnapshotPayload>`
    - `RelayHTTPReplayPayload`
- `MacRelayHTTPServerProbe`
  - 启动本地 server：`127.0.0.1:48731`
  - 用 `URLSession` 请求 `/snapshot`
  - 请求 `/replay?afterSeq=1&maxEvents=10`
  - 验证 session、assistantText、seq、replay events。

验证结果：

```text
MacRelayHTTPServerProbe passed port=48731 seq=4 replayEvents=3
```

说明：

- 当前 HTTP server 只在 probe 中启动，尚未接入 App 常驻启动。
- 原因是还需要补 pairing token / 鉴权 / 端口管理，避免过早扩大安全面。

##### 8. 当前验证命令

本轮持续使用以下命令做回归：

```bash
swift build
.build/debug/SandboxPayloadProbe
.build/debug/ThreadStartSchemaProbe /private/tmp/AgentClientM1Prototype read-only
.build/debug/TurnStartSchemaProbe /private/tmp/AgentClientM1Prototype read-only readOnly
.build/debug/TurnEventTraceProbe /private/tmp/AgentClientM1Prototype "Reply with exactly: ok"
.build/debug/SettingsUpdateSchemaProbe
.build/debug/SettingsUpdateLiveProbe /private/tmp/AgentClientM1Prototype
.build/debug/MacRelayServiceFixtureProbe
.build/debug/MacRelayHTTPServerProbe
.build/debug/RelayCoreFixtureProbe
.build/debug/RelayCommandFixtureProbe
.build/debug/AgentClientMacMock
.build/debug/CodexAppServerInitProbe /private/tmp/AgentClientM1Prototype
swift test
```

关键结果：

- `swift test`：48 tests, 0 failures。
- `MacRelayServiceFixtureProbe`：通过。
- `MacRelayHTTPServerProbe`：通过。
- 真实 Codex schema probes 均通过。

##### 9. 当前状态

已完成：

- Real mode `sendDraft` 跑通。
- sandbox schema 真实确认并修正。
- 连续消息回复错位 / 复读上一轮问题已修复。
- `thread/settings/update` 热切换已接通。
- Inspector Files 已接真实 `fileChanges`。
- MacRelayService 本地状态层已建立。
- Mac UI 已旁路接入 relay service。
- 本地 HTTP relay server skeleton 已通过 probe。

待做：

1. 将 `MacRelayHTTPServer` 接入 Mac App 生命周期。
   - 默认只监听 localhost。
   - 增加 start / stop 控制。
   - Inspector 显示端口和状态。
2. 增加 pairing token / 简单鉴权。
   - `/snapshot` 和 `/replay` 需要 token。
   - 为后续二维码配对准备 payload。
3. 从 HTTP 过渡到 WebSocket。
   - 支持双向 command。
   - 支持 heartbeat。
   - 支持 `snapshot.get` / `replay.from` / `session.turn.start`。
4. 命令 dispatcher 继续接真实 bridge。
   - `session.turn.start`
   - `session.settings.update`
   - `approval.resolve`
5. 移动端 / 模拟客户端开始消费 relay。
