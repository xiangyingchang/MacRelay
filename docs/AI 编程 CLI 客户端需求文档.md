# AI 编程 CLI 客户端需求文档

创建日期：2026-06-21

## 1. 背景与目标

希望做一个跨设备的 AI 编程 CLI 客户端。初期只支持 macOS 和 iPhone：

- macOS 端作为主工作端，负责扫描本机已安装的 AI 编程 CLI 工具，例如 Codex CLI、Claude Code 等，并提供统一的图形化会话入口。
- iPhone 端作为移动伴随端，通过二维码等方式与 Mac 端配对，连接后可以同步 Mac 上的 session，便于移动查看、继续输入、接收状态。

产品体验可以参考 Hermes Desktop：打开客户端后，用户能选择一个本地 CLI 工具进入，并在客户端内获得接近终端但更适合会话管理的交互体验。

更明确地说，产品目标有两个：

- 做一个能直接操作 Codex CLI 等本地 AI coding CLI 的可视化客户端，让终端里的 session 更容易浏览、恢复、控制和审查。
- 让配对后的 iPhone 能完整接手需要 Mac 环境才能处理的事情：Mac 继续负责执行、访问文件、调用本地 CLI 和使用本地凭证；iPhone 负责完整远程操控和决策。

## 2. 产品定位

这是一个“本地 AI 编程代理会话管理器”，不是自研大模型 IDE，也不是替代 Codex CLI / Claude Code 的工具链。

核心价值：

- 统一入口：把多个本地 AI 编程 CLI 工具收进一个客户端。
- 会话可视化：把终端里的 agent session 变成可管理、可恢复、可浏览的会话。
- 跨设备陪伴：Mac 上跑任务，iPhone 上看进度、发指令、接收提醒。
- 本地优先：尽量复用用户本机已有 CLI、认证、项目目录和权限模型。
- 隐私优先：提供接近 Lody 这类产品的移动端接手体验，但不把 conversation、diff、项目文件、凭证托管到自有服务器。

## 3. 用户场景

### 3.1 Mac 上启动一个 Codex CLI 会话

用户打开 Mac 客户端，客户端扫描本机环境，发现已安装 Codex CLI 和 Claude Code。客户端测试可用性后展示工具列表，用户选择 Codex CLI，进入会话界面。

用户选择一个项目目录，输入需求，客户端在背后启动对应 CLI 进程，并将 stdout / stderr / 交互输入映射到图形化界面。

### 3.2 Mac 上运行任务，手机上看进度

用户在 Mac 上启动一个长任务，例如修复 CI 或重构代码。离开电脑后，用户打开 iPhone 客户端，看到当前 session 的状态、最近输出、等待确认的问题，并可以继续回复。

### 3.3 手机远程输入，Mac 本地执行

iPhone 不直接执行 Codex / Claude Code，而是通过已配对的 Mac 发送消息。真正的 CLI 进程、项目文件访问、Git 操作仍发生在 Mac 本机。

手机端不是“只看进度”的通知面板，而是完整远程操作面。用户在手机上应能处理 Codex 等待输入、权限模式切换、Plan mode、模型选择、文件变更审查、approve / discard、终止任务、新建任务和选择项目目录。

### 3.4 多 CLI 工具统一管理

用户可以在一个客户端中管理 Codex CLI、Claude Code 等不同工具的会话。每个 session 记录其工具类型、项目目录、启动时间、状态和历史消息。

## 4. MVP 范围

### 4.1 macOS 端

MVP 必须支持：

- 启动时扫描本机是否安装目标 CLI：
  - Codex CLI
  - Claude Code
- 对已安装 CLI 做基础可用性测试：
  - 命令是否存在
  - 版本是否可读取
  - 是否能正常启动或通过健康检查
  - 是否需要登录或配置
- 用户选择默认工具后进入主界面。
- 支持选择项目目录。
- 支持启动一个新的 CLI session。
- 支持展示会话输出。
- 支持向 CLI session 发送用户输入。
- 支持会话列表：
  - 运行中
  - 已结束
  - 异常退出
- 支持基础 session 元数据：
  - 工具类型
  - 项目路径
  - 创建时间
  - 最近活动时间
  - 状态
- 支持与 iPhone 配对：
  - Mac 端生成二维码
  - iPhone 扫码连接
  - 展示已连接设备
  - 可断开设备
- 支持防休眠配置：
  - 运行 session 时禁止 Mac 休眠
  - 连接 iPhone 时禁止 Mac 休眠
  - 用户可手动关闭防休眠
  - App 退出、session 结束或设备断开后自动释放防休眠
- 支持常驻能力：
  - 可配置开机启动或登录后启动
  - 可作为菜单栏应用保持运行
  - 关闭主窗口后仍可保持 session 和 iPhone 连接
  - 明确展示当前是否允许移动端接管

MVP 暂不强求：

- 自建模型能力
- 完整 IDE 编辑器
- 多人协作
- 云端托管执行环境
- 插件市场
- 跨 Mac 同步
- Windows / Linux 客户端

### 4.2 iPhone 端

MVP 必须支持：

- 扫描 Mac 端二维码完成配对。
- 查看 Mac 上的 session 列表。
- 进入某个 session 查看最近对话和输出。
- 对运行中的 session 发送输入。
- 查看 Mac session 产生的 diff 和文件变更。
- 发起新的 session。
- 选择项目目录，允许浏览 Mac 当前用户可访问的整个用户目录。
- 终止运行中的 session。
- 对单个文件变更执行 approve / approve & stage / discard。
- 选择 Codex CLI 配置项，包括模型、reasoning effort、Plan mode、权限/沙箱模式等。
- 移动端能力原则上与 Mac 端保持一致：在 iPhone 上操作就像在 Mac 上操作同一个 Codex CLI 客户端。Mac 能做的主要操作，iPhone 端也应能触达；只是具体交互形态需要适配小屏。
- 显示 session 状态：
  - 运行中
  - 等待用户输入
  - 已完成
  - 失败
- 接收基础通知：
  - 任务完成
  - 任务失败
  - CLI 等待用户确认或输入
- 处理 Codex 等待确认 / 等待选择的状态：
  - approval prompt
  - Plan mode 后是否执行
  - 权限/沙箱越界请求
  - 命令失败后的重试选择
  - Codex 登录或本机权限缺失提醒

MVP 暂不强求：

- iPhone 本地执行 CLI。
- 离线编辑后自动合并。

## 5. Mac 端核心流程

### 5.1 首次打开

1. App 启动。
2. 扫描本机 PATH 和常见安装路径。
3. 检测 Codex CLI、Claude Code 等工具是否存在。
4. 读取版本和基础状态。
5. 展示工具选择页。
6. 用户选择一个工具作为当前默认工具。
7. 进入主会话界面。

### 5.2 工具扫描逻辑

建议先支持命令级检测：

- `codex --version`
- `claude --version`

需要进一步确认各 CLI 的健康检查命令和非交互启动方式。不同 CLI 的登录状态、项目权限、MCP 配置、沙箱策略可能差异较大，建议抽象成 Tool Adapter：

- `detect()`
- `getVersion()`
- `checkAuthStatus()`
- `startSession(projectPath, options)`
- `sendInput(sessionId, input)`
- `stopSession(sessionId)`
- `parseOutput(chunk)`

### 5.3 进入会话

用户选定工具和项目目录后，Mac 客户端启动 CLI 子进程。客户端应保留真实终端能力，但在 UI 上抽象为消息流：

- 用户输入
- assistant 输出
- 工具调用状态
- 等待确认
- 错误信息
- 任务完成

如果 CLI 输出格式不稳定，MVP 可以先使用 terminal-like 输出展示，但需要额外设计文件变更层：

- 通过 Git working tree 获取文件变更状态。
- 通过 `git diff` 或等价库生成 diff。
- Mac 和 iPhone 都展示同一份 diff 数据。
- diff 与 CLI 输出解耦，避免依赖单个 CLI 的输出格式。

### 5.4 文件变更 approve / discard 语义

approve / discard 是客户端对文件变更提供的操作层，需要明确它到底影响什么。

MVP 需要同时支持轻量审核和 Git 操作：

- approve：用户确认某个文件变更可以保留。等价为“客户端内标记该文件已审核通过”，不自动提交代码，也不自动 stage。
- approve & stage：用户确认某个文件变更可以进入 Git staged changes。等价为对该文件执行 `git add <file>`。
- discard session changes：丢弃该文件在本次 session 中产生的变更，保留 session 开始前已经存在的用户改动。
- discard all file changes：丢弃该文件当前所有未提交变更，恢复到 Git HEAD 或上一个明确基线。这是高风险操作，需要更强提示。
- approve 不等于 `git commit`。
- discard 是破坏性操作，只作用于用户选择的单个文件，不批量影响其他文件。
- approve / discard 操作由 iPhone 发起时，仍在 Mac 本机执行。

推荐交互：

- 默认主按钮是 approve，用于标记审核通过。
- 次级按钮是 stage，用于把已确认文件加入 Git staged changes。
- discard 默认只丢弃本次 session 产生的变更。
- discard all file changes 放在更多菜单中，并在 iPhone 和 Mac 上都展示明确风险提示。

## 5.5 双端 Session 级 Codex CLI 运行配置

产品原则：Mac 和 iPhone 都必须能在 session 维度灵活配置 Codex CLI 的关键运行参数。iPhone 不是只读监控端，而是完整 Codex CLI 操作端。

这些配置不是单纯的全局 App 设置，也不是只写入 `~/.codex/config.toml` 的长期默认项。它们应该是每个 session / 每次任务发起前可以快速选择的运行上下文，交互上更接近输入框附近的 session toolbar：

- 当前 agent / 工具，例如 Codex。
- 当前模型，例如 5.5。
- 当前 reasoning effort，例如 Medium。
- 当前目标 Mac / 工作目录。
- Plan mode 开关。
- 访问权限模式，例如只读、默认、完全访问。
- 上传图片、发送等输入辅助操作。

全局设置只作为默认值来源；真正启动或继续某个 session 时，以该 session 当前选择的配置为准。

MVP 双端都需要支持：

- 模型选择：
  - 展示 Codex CLI 当前可用模型列表。
  - 支持启动 session 前在 session toolbar 中选择模型。
  - 支持 session 中切换模型，映射 Codex CLI `/model` 能力。
  - 支持展示当前 active model。
- Reasoning effort：
  - 支持 `low`、`medium`、`high`、`xhigh`。
  - 如当前 Codex CLI / model catalog 暴露 `none`、`minimal` 等额外值，也应透传展示。
  - 启动 session 前可在 session toolbar 中选择 `model_reasoning_effort`。
  - Plan mode 可单独配置 `plan_mode_reasoning_effort`。
- Plan mode：
  - 支持打开 / 关闭 Plan mode。
  - 映射 Codex CLI `/plan` 能力。
  - 用户可在手机端要求 Codex 先规划，再决定是否执行。
- 权限/沙箱模式：
  - 只读：映射 Codex Read-only，适合浏览、提问、规划，不主动修改文件。
  - 默认 / Auto：映射 workspace-write + on-request approvals，允许在工作区内读写和运行常规命令，越界时请求批准。
  - 完全访问：映射 Full Access / danger-full-access + never approvals，允许跨机器范围操作并减少批准打断。需要明确风险提示。
- Approval policy：
  - 支持 `untrusted`、`on-request`、`never`。
  - 普通用户界面优先展示“只读 / 默认 / 完全访问”三个产品化选项，高级设置里再展示底层 policy。
- Sandbox mode：
  - 支持 `read-only`、`workspace-write`、`danger-full-access`。
  - 与权限模式联动展示，避免用户同时理解两套概念。
- Web search：
  - 支持 cached / live / disabled。
  - live web search 需要提示网络和 prompt injection 风险。
- Profile：
  - 支持选择 Codex profile。
  - profile 用于复用一组模型、权限、provider、MCP 等配置。
- Fast mode：
  - 如果当前模型 catalog 支持 Fast tier，双端都应能切换。
  - 如果当前模型不支持，隐藏或置灰。
- Personality / communication style：
  - 如果当前 Codex CLI 支持 personality，双端可支持选择 pragmatic / friendly / none。
- 状态查看：
  - 双端都需要展示当前模型、reasoning effort、Plan mode、权限模式、sandbox、approval policy、工作目录、连接设备和 session 状态。

实现原则：

- 优先调用 Codex CLI / app-server 已支持的命令和协议能力。
- 对 Codex CLI 尚未提供结构化 API 的配置项，先通过启动参数、`--config key=value` 或 slash command 方式桥接。
- 客户端 UI 不硬编码过多模型名，模型列表应尽量从 Codex CLI 的模型 catalog 或 debug models 能力读取。
- 配置变更必须在 Mac 和 iPhone 双端实时同步。
- Session 级配置需要持久化到 session 元数据中，恢复 session 时应还原该 session 的模型、reasoning effort、Plan mode、权限模式等。
- 全局配置页只用于设置默认选项，例如默认模型、默认 reasoning effort、默认权限模式；用户在 session toolbar 的选择优先级更高。

## 6. 交互体验参考

详细 UI 设计基准见：[[AI 编程 CLI 客户端 UI 设计基准]]

参考 Hermes Desktop 的方向：

- 左侧：session 列表、工具选择、项目入口。
- 中间：当前 session 对话流。
- 底部：输入框。
- 顶部：当前工具、项目路径、连接设备、运行状态。
- 右侧可选：session 详情、文件变更、日志、手机连接状态。

体验原则：

- 不把用户困在“纯终端”里，但保留终端的透明度。
- 重要状态必须显性化，例如等待确认、正在执行、失败、已完成。
- 让用户明确知道当前使用的是哪个 CLI、在哪个项目目录、以什么权限运行。
- 默认沿用 CLI 自身权限和认证，不在 MVP 中重新设计账号体系。

### 6.1 设计品味要求

产品设计品味要求较高，视觉和交互应参考 Hermes Desktop 与 Lody 这类产品的克制、清晰和高密度工作流表达。

设计原则：

- 工具感强，不做营销化、装饰化界面。
- 信息密度高，但层级清楚，适合长时间工作。
- 输入区附近提供 session toolbar，快速切换 agent、模型、reasoning effort、Plan mode、权限模式、附件等。
- 会话、文件、diff、终端输出、状态提示应该在一个工作台里自然切换，而不是分裂成多个割裂页面。
- 状态要可读：运行中、等待用户、等待权限、Plan mode、失败、完成、Mac 离线、重连中，都要一眼可见。
- 移动端不是桌面端缩小版，而是为小屏重排后的完整操作面。
- 少用大面积卡片、渐变、空洞插画；优先使用清晰的列表、分栏、工具条、diff、文件树、状态标签。
- 对代码、diff、路径、终端输出使用优秀的等宽字体和类似 VS Code 的语法高亮风格。
- 高风险动作要清楚但不打扰：完全访问、discard all file changes、终止 session、吊销设备等要有明确视觉区分。

### 6.2 Lody 设计参考与差异

Lody 的公开说明中，有几类设计值得参考：

- 任务并行与 worktree 隔离：一个任务一个隔离工作区，降低多 agent 并行互相污染的风险。
- 实时 diff：每轮对话后展示本轮文件变更，也能查看整个 conversation 的 changes。
- 文件树：当前会话下的文件和变更保持可见。
- 移动优先：手机端能看实时终端输出、文件变更、session diff、通知和 approval。
- 后台 daemon：本地 runtime 可在后台保持运行，供桌面、Web、移动端连接。
- 可操作通知：任务完成、agent 需要 approval、PR ready 等事件可以通知用户。

但本产品与 Lody 的关键差异是隐私和部署模型：

- Lody 更偏云端协作工作流，包含账号、团队、GitHub 集成、服务端同步等能力。
- Lody 的隐私政策显示会收集用户提交的 conversation content 和 workflow context，并使用第三方基础设施与分析/监控服务。
- 本产品第一版明确 local-first：不做云端中继，不做账号体系，不把 conversation、diff、项目文件、凭证同步到自有服务器。
- Mac 是唯一执行和数据源，iPhone 通过局域网连接 Mac；所有本地代码、Codex 登录态、Git 凭证、API key 都留在 Mac。

可以借鉴 Lody 的产品品味和工作流表达，但不能复制其云端数据路径。本产品的差异化卖点应是“Lody-like 的移动接手体验 + 本地优先隐私模型”。

## 7. Mac 与 iPhone 连接方案

### 7.1 配对方式

MVP 推荐二维码配对：

1. Mac 端生成一次性 pairing token。
2. 二维码中包含 Mac 端连接地址、token、公钥或配对挑战信息。
3. iPhone 扫码后发起连接。
4. Mac 端确认配对成功并记录设备。
5. 后续 iPhone 使用设备凭证重连。

### 7.2 连接模式

需要在以下方案中选择：

方案 A：局域网直连

- Mac 在本地启动轻量服务。
- iPhone 扫码后在同一 Wi-Fi 下连接 Mac。
- 优点：本地优先，隐私更好，架构简单。
- 缺点：不在同一网络时不可用；NAT、公司网络、系统防火墙可能影响连接。

方案 B：云端中继

- Mac 和 iPhone 都连接到云端 relay。
- 云端只转发加密消息，不执行 CLI。
- 优点：跨网络可用，移动场景更强。
- 缺点：需要账号体系、服务端成本、安全设计更复杂。

方案 C：先局域网，后云端中继

- MVP 先做局域网直连。
- 后续引入云端中继解决远程访问。
- 这是当前确认路线：第一版只支持局域网直连，不做账号体系和云端中继。

### 7.3 同步内容

MVP 同步：

- session 列表
- session 状态
- 最近消息和输出
- 用户输入
- 文件变更状态
- diff 内容
- approve / approve & stage / discard 单文件变更操作
- Codex CLI 当前 session 运行配置状态：
  - 模型
  - reasoning effort
  - Plan mode
  - 权限/沙箱模式
  - approval policy
  - web search
  - profile
  - fast mode
- 新建 session 操作
- 选择项目目录操作，允许浏览 Mac 当前用户可访问的整个用户目录
- 终止 session 操作
- 防休眠配置状态
- 任务完成 / 失败 / 等待输入通知
- Codex approval prompt / permission prompt
- Plan mode 的计划结果和执行确认状态
- 命令执行状态、退出码、可重试状态
- 连接心跳和断线重连状态

暂不同步：

- 完整项目文件
- 用户密钥
- CLI 登录凭证
- 大量历史日志
- Git 凭证

### 7.4 连接保活与断线恢复

为了让 iPhone 能持续接手 Mac 上的任务，MVP 需要把连接可靠性作为核心能力，而不是附属能力。

必须支持：

- Mac 端持续监听局域网连接，App 主窗口关闭后仍可保持后台服务。
- iPhone 端断线后自动重连。
- 双端维持 heartbeat，明确展示在线、离线、重连中、Mac 不可达。
- 重连后恢复：
  - session 列表
  - 当前 session 状态
  - 最近输出
  - 当前等待用户处理的问题
  - 当前 diff / 文件变更
  - 当前 session 级运行配置
- Mac 端进入睡眠、锁屏、网络切换、App 被退出时，iPhone 端要给出明确状态。

边界：

- MVP 已确认只做局域网直连，所以 iPhone 和 Mac 不在同一局域网时默认不可连接。
- 后续如果要支持离开局域网后的远程接管，需要增加 VPN / Tailscale 指引、Bonjour over peer-to-peer、或云端中继能力。

### 7.5 可操作通知

移动端通知不应只是“任务完成提醒”，还要帮助用户接手 Mac 上的阻塞点。

MVP 通知类型：

- Codex 等待用户输入。
- Codex 等待权限/沙箱确认。
- Codex Plan mode 输出了计划，等待用户决定是否执行。
- 任务完成。
- 任务失败。
- Mac 即将睡眠或已不可达。
- iPhone 与 Mac 断开连接。

通知策略：

- 锁屏通知默认不展示敏感代码和路径细节，只展示摘要。
- 用户可在设置中选择是否展示更详细内容。
- 点击通知应直接进入对应 session 和待处理状态。

## 8. 安全与权限

这是产品能否成立的关键。

基础原则：

- CLI 执行只发生在 Mac 本机。
- iPhone 是 Mac 客户端的等价远程操作面；执行仍只发生在 Mac 本机。
- iPhone 端允许浏览 Mac 当前用户可访问的整个用户目录，但不直接获取 Mac 的密钥或凭证。
- 配对 token 必须短期有效、一次性使用。
- 手机端不能直接拿到 Mac 上的 API Key、SSH Key、Git 凭证。
- 用户需要能随时断开或删除已配对设备。
- 已确认手机端输入不需要 Mac 端二次确认。iPhone 端被视为同一用户的受信任遥控端。
- iPhone 端允许发起新 session、浏览用户目录并选择项目目录、终止 session、approve / approve & stage / discard 单文件变更。
- iPhone 端允许切换当前 session 的模型、reasoning effort、Plan mode、权限/沙箱模式等 Codex CLI 运行配置。

### 8.1 移动端接手边界

iPhone 的目标是完整接手 Codex CLI 操作，但仍有一些事情必须由 Mac 本机完成或授权。

Mac 本机负责：

- 执行 Codex CLI 子进程。
- 读取和修改项目文件。
- 使用本机 Git、SSH、Keychain、API key、Codex 登录态。
- 弹出系统权限请求，例如本地网络权限、文件夹访问权限、辅助功能权限、Full Disk Access 等。
- 处理必须在 Mac 浏览器中完成的登录流程。

iPhone 可远程处理：

- Codex 用户输入。
- Codex approval prompt / permission prompt。
- Plan mode 后的继续执行。
- session 级配置切换。
- 文件变更审查。
- 单文件 approve / stage / discard。
- 新建、终止、恢复 session。

iPhone 不能直接获取：

- API key 原文。
- SSH private key。
- Git 凭证。
- Codex auth token。
- Keychain secret。

如果 Codex 登录、Git 凭证、系统权限或浏览器 OAuth 阻塞任务，iPhone 端应展示明确提示：这是 Mac 本机授权事项，需要回到 Mac 处理。处理完成后，iPhone 可继续接手后续流程。

### 8.2 设备信任与吊销

由于 iPhone 被视为受信任远程操作端，设备管理必须足够清晰。

MVP 必须支持：

- Mac 端查看已配对设备列表。
- 展示设备名称、首次配对时间、最近连接时间、当前在线状态。
- Mac 端一键吊销某台 iPhone。
- iPhone 端退出配对。
- 配对 token 一次性、短有效期。
- 设备凭证存储在 iOS Keychain 和 macOS Keychain。
- 断开或吊销后，iPhone 不能继续发送任何 session 控制指令。

建议支持：

- iPhone 打开 App 后用 Face ID / Touch ID 解锁远程控制能力。
- 切换到完全访问、discard all file changes、终止 session 等高风险动作，可要求 iPhone 本机生物识别确认。

待确认：

- 是否完全复用 CLI 自己的权限确认机制，作为唯一的高风险操作确认层。
- iPhone 端发出的输入默认允许触发所有 CLI 行为，但需要清晰展示当前连接设备，并支持随时吊销设备。
- 手机端是否可以在锁屏通知中展示敏感内容。

## 9. 技术架构草案

Mac Relay 详细设计见：[[AI 编程 CLI 客户端 Mac Relay 技术设计]]

### 9.1 客户端技术选型

可选路线：

- Mac：Swift / SwiftUI 原生
- iPhone：Swift / SwiftUI 原生
- 共享通信协议：WebSocket / gRPC / custom JSON-RPC
- 本地存储：SQLite

另一条路线：

- Mac：Electron / Tauri
- iPhone：Swift 原生

最终建议：

- 推荐使用 Swift / SwiftUI 原生双端。
- Mac 端和 iPhone 端共用一个 Swift Package，沉淀核心模型和协议：
  - Session model
  - Tool adapter protocol
  - Sync protocol
  - Diff model
  - Pairing / auth model
- macOS 端使用 SwiftUI + AppKit bridge：
  - SwiftUI 负责主界面。
  - AppKit/低层系统 API 负责 PTY、进程管理、菜单栏、文件权限、复杂文本视图等。
- iPhone 端使用 SwiftUI 原生实现。
- 局域网发现使用 Bonjour / Network framework 方向。
- 通信协议第一版建议使用 WebSocket + JSON 消息，后续可以升级为更严格的 binary protocol 或 gRPC-like 协议。

不优先推荐 Electron：

- Electron 适合快速做桌面跨平台，但 iPhone 端仍然需要另写原生 App。
- 该产品第一阶段只支持 macOS + iPhone，Electron 的跨 Windows/Linux 优势暂时用不上。
- 长期会遇到 macOS 权限、PTY、Keychain、局域网、通知、App Store 分发等原生能力，Electron 会增加桥接复杂度。

不优先推荐 Tauri：

- Tauri 比 Electron 更轻，并且支持桌面和移动端方向。
- 但此产品核心不是普通 Web UI 壳，而是深度 Apple 平台集成：PTY、进程控制、文件权限、Keychain、Bonjour、通知、diff 浏览、iPhone 小屏原生交互。
- 如果团队更熟 Web/Rust，可以把 Tauri 作为备选；但从长期产品质量和 Apple 生态一致性看，Swift/SwiftUI 更合适。

### 9.2 Mac 端模块

- Tool Detector：扫描和检测本地 CLI。
- Tool Adapter：封装不同 CLI 的启动、输入、停止、输出解析。
- PTY / Process Manager：管理子进程和伪终端。
- Session Store：存储 session 元数据和历史输出。
- Sync Server：负责 iPhone 配对、鉴权、消息同步。
- Connection Supervisor：维护 heartbeat、断线重连、连接状态和设备在线状态。
- File Browser：向 iPhone 提供 Mac 用户目录浏览、项目选择和权限错误处理。
- Diff Manager：生成 diff、跟踪文件变更、执行 approve / approve & stage / discard。
- Codex Config Manager：读取、展示、切换 Codex CLI session 级运行配置，包括模型、reasoning effort、Plan mode、权限/沙箱、approval policy、profile、web search 等。
- Prompt / Approval Router：识别 Codex 等待输入、权限确认、Plan mode 执行确认，并路由到 Mac 和 iPhone 双端。
- Sleep Prevention Manager：按用户配置控制 Mac 防休眠，保障移动端持续连接。
- Notification Manager：把 session 状态转换为本地和远端通知。
- Device Trust Manager：管理配对设备、设备凭证、吊销状态和本机生物识别策略。
- UI Shell：会话列表、会话视图、设置页。

### 9.3 iPhone 端模块

- Pairing：扫码配对。
- Device Auth：保存设备凭证。
- Session List：展示 Mac session。
- Session Controller：发起、查看、输入、终止 Mac session。
- Project Picker：浏览 Mac 当前用户可访问的整个用户目录，并选择项目目录。
- Diff Viewer：查看文件变更和代码 diff，支持 approve / approve & stage / discard 单文件变更。
- Session Toolbar / Codex Settings Panel：在当前 session 下切换模型、reasoning effort、Plan mode、权限/沙箱、approval policy、profile、web search、fast mode 等。
- Prompt / Approval Inbox：处理 Codex 等待输入、权限确认、Plan mode 执行确认和失败重试。
- Push / Local Notification：接收状态更新和可操作通知。
- Connection Manager：处理断线重连。

## 10. 关键待确认问题

### 10.1 产品边界

- 这是面向开发者个人使用，还是团队协作工具？
- 是否需要账号体系？如果 MVP 只做局域网直连，是否可以先不做账号？
- 产品是否只作为“多个 CLI 的壳”，还是未来要提供自己的 agent 编排层？
- 是否希望支持非编程类 CLI agent，还是先聚焦 AI coding？

### 10.2 CLI 支持范围

- MVP 已确认先只支持 Codex CLI。Claude Code、Gemini CLI、Cursor Agent 等作为后续 adapter 扩展。
- 每种 CLI 是否需要完整结构化解析，还是先以 terminal 输出为主？
- CLI 登录状态如何判断？
- CLI 升级或输出格式变化时，客户端如何兼容？

### 10.3 Session 定义

- session 是 CLI 原生 session，还是客户端自己定义的一次子进程运行？
- 是否需要恢复已经退出的 session？
- session 历史保存多久？
- 是否保存完整 stdout/stderr？
- 是否允许用户搜索历史 session？

### 10.4 iPhone 同步深度

- iPhone 已确认需要查看文件 diff / 文件变更。
- iPhone 端能力原则上与 Mac 端保持一致：在 iPhone 上操作就像在 Mac 上操作同一个 Codex CLI 客户端。
- 已确认允许 iPhone 发起新 session。
- 已确认允许 iPhone 浏览 Mac 当前用户可访问的整个用户目录，并选择项目目录。
- 已确认允许 iPhone 终止 Mac 上的 session。
- 已确认允许 iPhone 对单个文件变更执行 approve / approve & stage / discard。
- 已确认 iPhone 端需要在当前 session 下支持选择模型、reasoning effort、Plan mode、只读 / 默认 / 完全访问等 Codex CLI 运行配置。
- 已确认手机端输入不需要 Mac 端二次确认。

### 10.5 Session 级 Codex CLI 配置映射

- 双端都需要支持 Codex CLI 本身支持的 session 运行配置项，而不是只做客户端私有配置。
- 这些配置优先作用于当前 session；全局配置只作为默认值。
- 模型选择映射 `--model` / `/model` / `model` 配置。
- Reasoning effort 映射 `model_reasoning_effort`，Plan mode 可映射 `plan_mode_reasoning_effort`。
- Plan mode 映射 `/plan`。
- 只读映射 Read-only / `sandbox_mode = "read-only"`。
- 默认 / Auto 映射 `sandbox_mode = "workspace-write"` + `approval_policy = "on-request"`。
- 完全访问映射 Full Access / `sandbox_mode = "danger-full-access"` + `approval_policy = "never"`。
- Profile 映射 `--profile` 和对应 profile config。
- Web search 映射 `web_search = "cached" | "live" | "disabled"`。
- Fast mode 映射 `/fast` 或当前模型 catalog 暴露的 fast service tier。
- 仍需技术调研：哪些配置项可以在 active session 中无损切换，哪些只能在新 session 启动时生效；不能热切换的配置，应在 UI 上提示“下个 session 生效”或触发新 session。

### 10.6 网络与安全

- MVP 已确认接受“必须 Mac 和 iPhone 在同一局域网”。
- 是否需要支持外网远程访问？
- 是否需要云端 relay？
- 手机丢失时如何吊销访问？
- 是否需要端到端加密？
- 高风险命令如何识别和拦截？
- iPhone 浏览整个用户目录时，是否需要隐藏特定敏感目录，例如 `.ssh`、`.gnupg`、密码管理器目录、浏览器配置目录？
- 手机端切换到完全访问时，是否需要额外风险提示或本机生物识别确认？

### 10.7 商业化与分发

- 是个人工具、开源工具，还是商业 SaaS？
- Mac 端是否通过 App Store 分发？如果不是，如何处理签名、公证和权限提示？
- iPhone 端是否上架 App Store？如果上架，远程执行和开发者工具属性是否有审核风险？
- 是否需要订阅收费？如果没有云服务，收费点是什么？

## 11. 风险列表

- 不同 CLI 的交互协议不统一，结构化体验难度高。
- CLI 工具可能频繁变化，adapter 维护成本高。
- macOS 沙箱、权限、pty、文件访问会影响 App Store 分发。
- iPhone 远程控制 Mac 执行命令存在安全和审核风险。
- 局域网连接在真实网络环境中不稳定。
- macOS 睡眠、锁屏、网络切换、防火墙、本地网络权限会影响 iPhone 持续接管。
- Codex 登录、系统权限、浏览器 OAuth 等 Mac-only 授权会阻塞手机端完整接手。
- 手机端浏览整个用户目录价值高，但敏感目录和凭证泄露风险也更高。
- app-server / CLI 输出和 prompt 结构化能力如果不足，可能需要先做 terminal-like 兼容层。
- 如果引入云端中继，安全、隐私、成本和账号体系复杂度上升。
- 手机端如果只能看文本，用户价值可能不足；如果能操作太多，安全风险又上升。

## 12. 建议的第一阶段原型

目标：验证“Mac 上包装 Codex CLI session，并用 iPhone 查看、输入和浏览文件变更”是否有足够价值。

范围：

- Mac 端只支持手动配置 CLI 路径 + 自动检测 PATH。
- 只支持 Codex CLI 一个工具，后续再用 Claude Code 作为第二个 adapter 验证扩展性。
- session 输出先用 terminal-like 文本流，不急于结构化解析。
- diff / 文件变更通过 Git working tree 独立获取，不依赖 Codex CLI 输出格式。
- Mac 和 iPhone 双端都支持当前 session 的 Codex CLI 关键运行配置：模型、reasoning effort、Plan mode、只读 / 默认 / 完全访问、approval policy、sandbox mode。
- iPhone 通过局域网二维码配对。
- iPhone 支持查看当前 session、发送输入、发起新 session、浏览 Mac 用户目录并选择项目目录、终止 session、查看 diff / 文件变更、approve / approve & stage / discard 单文件变更。
- iPhone 支持处理 Codex 等待输入、权限确认、Plan mode 执行确认、失败重试等阻塞点。
- 支持 heartbeat、断线重连和状态恢复。
- Mac 支持防休眠配置，保证运行 session 或连接 iPhone 时持续在线。
- 不做账号体系，不做云端中继，不同步文件。

成功标准：

- 用户能在 Mac 客户端中成功启动 Codex CLI。
- 用户能从 iPhone 看到 Mac session 输出。
- 用户能从 iPhone 向 session 发送输入并影响 Mac 上的 CLI。
- 用户能从 iPhone 发起和终止 Mac 上的 session。
- 用户能从 iPhone 浏览 Mac 当前用户可访问的目录，并选择项目目录。
- 用户能从 iPhone 查看当前项目的文件变更和 diff。
- 用户能从 iPhone approve / approve & stage / discard 单个文件变更。
- 用户能在 Mac 和 iPhone 双端为当前 session 选择模型和 reasoning effort。
- 用户能在 Mac 和 iPhone 双端为当前 session 切换 Plan mode。
- 用户能在 Mac 和 iPhone 双端为当前 session 选择只读 / 默认 / 完全访问等权限模式。
- 用户能从 iPhone 处理 Codex 的等待输入、权限确认、Plan mode 执行确认。
- 用户能在 Mac 端配置运行 session 或连接 iPhone 时禁止休眠，移动端连接可以持续保持。
- Mac 端能明确展示连接设备和 session 状态。
- 断线重连后 iPhone 能恢复最近 session 状态。
- Mac 端被吊销的 iPhone 不能继续控制任何 session。

## 13. 下一步行动

1. 已确认 MVP 先只做局域网直连。
2. 已建议第一版技术栈：Swift / SwiftUI 原生双端，共用 Swift Package 核心层。
3. 调研 Codex CLI 的启动、恢复、登录检测和输出行为。
4. 调研 Codex CLI session 级配置项的结构化读取和切换能力，重点是模型、reasoning effort、Plan mode、权限/沙箱、profile、web search。
5. 画一版 Mac 主界面和 iPhone session 页线框图。
6. 做 Mac 本地 CLI detector + pty session 的技术原型。
7. 做二维码配对 + WebSocket 消息同步原型。

## 14. PRD 评审结论

当前 PRD 的主线已经成立：

- Mac 端是本地执行与可视化控制中心。
- iPhone 端是完整远程操作端，而不是只读监控端。
- 执行、文件访问、Git、Codex 登录态和本机凭证都留在 Mac。
- iPhone 通过局域网配对接管 session、输入、配置、diff、approval、Plan mode 和文件变更决策。

后续进入原型前，最需要验证的不是 UI，而是技术可行性：

- Codex CLI / app-server 是否能提供足够结构化的 session、prompt、approval、diff、config 状态。
- 如果结构化能力不足，是否能接受第一版用 PTY + terminal-like 输出兜底。
- session 级配置哪些能热切换，哪些只能新 session 生效。
- 手机端处理 approval prompt 时，如何可靠地映射回 Codex CLI 的真实输入/选择。
- iPhone 浏览整个用户目录时，敏感目录是否需要默认隐藏。
- 局域网连接在 Mac 锁屏、睡眠、切 Wi-Fi、防火墙场景下的可用性。

## 15. 落地执行建议

这份 PRD 已经可以开始落地，但建议分阶段推进，不要直接进入完整产品开发。

### 15.1 M0 技术验证

目标：验证最关键的不确定性。

必须完成：

- Mac App 能检测并启动 Codex CLI。
- Mac App 能通过 PTY 或 app-server 方式收发 Codex session 输入输出。
- iPhone 能通过局域网扫码连接 Mac。
- iPhone 能看到 session 输出并发送输入。
- iPhone 能处理一个 Codex 等待输入或确认的场景。
- Mac 端能生成 Git diff，并同步到 iPhone 展示。
- 双端能展示并切换至少三个 session 级配置：模型、reasoning effort、权限模式。
- Mac 防休眠和后台常驻能跑通。

M0 成功后再进入完整 UI 和产品化实现。

### 15.2 M1 产品原型

目标：做出可日常试用的本地优先版本。

范围：

- Mac 主界面：session 列表、当前会话、session toolbar、diff / files 面板、设备连接状态。
- iPhone 主界面：session 列表、会话详情、输入、session toolbar、diff / files、approval inbox。
- 配对、断线重连、设备吊销。
- 可操作通知。
- approve / approve & stage / discard。

### 15.3 M2 可用性打磨

目标：提升为高品味、可长期使用的客户端。

重点：

- UI 细节对齐 Hermes Desktop / Lody 级别的工作流质感。
- diff、代码高亮、终端输出、状态提示、移动端小屏操作体验打磨。
- session 搜索、历史恢复、文件树性能优化。
- 更完善的隐私和安全提示。
- 第二个 CLI adapter，例如 Claude Code。
