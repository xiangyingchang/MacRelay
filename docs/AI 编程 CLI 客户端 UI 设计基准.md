# AI 编程 CLI 客户端 UI 设计基准

创建日期：2026-06-21  | 最后更新：2026-06-27

> **实现更新：**
> - 2026-06-27：补充当前实际实现的 UI 布局、Inspector 结构、iOS 页面信息
> - 原始 UI 设计基准仍作为长期视觉参考，本节录当前实现状态

关联文档：

- [[AI 编程 CLI 客户端需求文档]]
- [[AI 编程 CLI 客户端落地执行计划]]

## 1. 参考对象

### 1.1 Hermes Desktop / Hermes One

参考来源：

- GitHub：<https://github.com/fathah/hermes-desktop>
- README：<https://github.com/fathah/hermes-desktop/blob/main/README.md>

已确认事实：

- Hermes Desktop 是一个 Electron / Vite / React / Tailwind 桌面应用。
- 它围绕本地或远程 Hermes backend 提供 GUI。
- README 明确包含 streaming chat UI、SSE streaming、tool progress、markdown rendering、syntax highlighting、token usage、session management、profile switching、models、tools、skills、settings 等能力。
- 它的产品形态适合作为“本地 agent GUI 工作台”的参考。

可借鉴点：

- 左侧高密度导航和 session 管理。
- 中央 streaming conversation 主工作区。
- 底部输入区和 slash command / model / tool 配置入口。
- 工具进度、token、状态、日志等信息在工作流中自然出现。
- 设置、模型、工具、skills、profiles 等能力分区清楚。

2026-06-21 源码与预览补充观察：

- 仓库结构：
  - `src/renderer/src/screens/Layout/Layout.tsx`：全局 shell、左侧导航、active sessions bar、profile switcher。
  - `src/renderer/src/screens/Layout/SidebarRecentSessions.tsx`：左栏内嵌近期会话列表。
  - `src/renderer/src/screens/Layout/ActiveSessionsBar.tsx`：顶部浏览器 tab 式会话切换条，也承担 titlebar/drag strip。
  - `src/renderer/src/screens/Chat/ChatInput.tsx`：多行输入 + 附件 + 语音 + model/folder extras + send/stop 的复合 composer。
  - `src/renderer/src/screens/Chat/ModelPicker.tsx`：可搜索模型下拉。
  - `src/renderer/src/screens/Chat/ReasoningEffortPicker.tsx`：reasoning effort 下拉，带说明与当前选中态。
  - `src/renderer/src/screens/Chat/MessageRow.tsx`：消息、avatar、copy、approval prompt、markdown/code 渲染。
  - `src/renderer/src/assets/main.css`：主题变量、sidebar、active session、chat input、message bubble 样式。
- 预览图重点：
  - `previews/chat.png`：左栏主导航 + Chat 下的近期会话，中央空状态，底部大 composer。
  - `previews/sessions.png`：session 管理页使用搜索、日期分组、横向 session card，信息密度高。
  - `previews/models.png`：模型页使用 pill filters + 双列大卡片，状态和 provider 标签低对比。
- Hermes 的优秀点不是复杂视觉，而是结构稳定：
  - 左侧固定全局导航。
  - Chat 下直接嵌近期 session，不额外跳页。
  - 顶部 active session bar 支持多会话并行。
  - 底部 composer 是核心操作区，不只是输入框。
  - 控件默认低对比，选中态用深蓝 accent 和轻背景表达。
  - 大多数元素 8-12px 圆角，避免过度“气泡化”。
  - 内容页保留大面积平面背景，卡片只用于列表项或明确对象。

对本产品的具体落地规则：

- Mac 端应采用 Hermes 风格的“全局左栏 + session 工作区”，而不是只做三栏 inspector。
- 左栏分两级：
  - 一级：Codex、Sessions、Files、Approvals、Models、Settings 等导航。
  - 二级：当前 Codex 下的近期/活动 session 列表。
- 顶部增加 active session bar：
  - 支持多个 Codex session 同时运行。
  - running session 显示 spinner / status。
  - 可关闭/终止 session。
- 底部 composer 升级为复合控制区：
  - 上层多行输入。
  - 下层工具栏放 attachment、model、effort、Plan、permission、cwd、send/stop。
  - 这些配置仍然是 session-scoped。
- 右侧 Inspector 保留，但角色要收敛：
  - 只展示当前 session 的 files、diff、approval、logs。
  - 不承担全局导航和模型管理。
- 视觉基调：
  - v3 优先做暗色工作台版本，因为 Hermes 的高密度暗色方案更适合长时间 coding。
  - 颜色采用中性暗底 + 单一深蓝 accent + 少量 warning/success。
  - 不使用渐变、装饰图、营销式 hero。
- 消息区：
  - 历史消息静态。
  - 只有当前 turn 显示 running / streaming / tool progress。
  - tool / approval / diff 作为事件块嵌入消息流，不做裸日志。

不直接照搬点：

- Hermes 是 Electron 技术栈；本产品第一版推荐 Swift / SwiftUI 原生双端。
- Hermes 面向 Hermes Agent 生态；本产品第一版面向 Codex CLI app-server。
- Hermes 支持本地/远程 backend；本产品第一版坚持局域网直连和 local-first，不做云端账号体系。

### 1.2 Lody

参考来源：

- 官网：<https://lody.ai/>
- 文档：<https://lody.ai/docs>
- 隐私政策：<https://lody.ai/privacy>

已确认事实：

- Lody 主张在 desktop 和 mobile 上运行 coding agents。
- 官网强调 worktree isolation、in-context diff、real-time file tree、mobile-first、approval from phone。
- 文档显示它支持 Claude Code、Codex、OpenCode、Kimi、自定义 ACP agents 等 runtime。
- 文档强调 session tabs、file list、diff viewer、diff comments、notifications、daemon mode、CLI runtime types、worktrees 等能力。
- 隐私政策显示其服务会收集用户提交的 conversation content 和 workflow context，并使用 Cloudflare、Convex、GitHub、PostHog、Sentry 等第三方服务。

可借鉴点：

- 手机端不是通知面板，而是完整工作流接管面。
- 每个任务有清晰边界，文件树和 diff 始终可见。
- 任务完成、approval、PR / CI 等事件应可通知和直达。
- 后台 daemon / relay 是跨设备体验的底座。
- diff review 和 approval 是移动端核心能力，不是附属能力。

必须区分点：

- Lody 更偏云端协作和团队同步。
- 本产品第一版不把 conversation、diff、项目文件、凭证同步到自有服务器。
- 本产品核心卖点是：Lody-like 的移动接手体验 + Mac 本地执行 + 局域网直连 + 隐私优先。

## 2. 产品界面原则

整体方向：高密度、克制、专业、长期可用。它应该像开发者每天打开的工作台，而不是营销页面或玩具聊天框。

原则：

- 信息密度高，但层级必须清楚。
- 默认展示工作所需内容：session、当前项目、模型、权限、输出、待处理事项、diff。
- 不做大面积装饰、渐变背景、空洞插图或营销式 hero。
- 不用多层卡片堆叠工作区；主界面应是清晰分栏和工具条。
- 所有危险状态必须可见：完全访问、跨目录访问、discard、终止 session、Mac 离线、iPhone 已接管。
- iPhone 不是 Mac 端缩小版，而是把同一能力重排为小屏任务流。
- 会话、文件、diff、approval、配置不应分裂成彼此断开的页面，应围绕同一个 session 组织。

## 3. Mac 主界面基准

推荐布局：三栏 + 底部输入区。

### 3.1 左栏：Session / Project Rail

内容：

- 当前 CLI 工具：Codex，后续 Claude Code。
- 项目目录入口。
- session 列表。
- 运行状态：运行中、等待用户、等待 approval、完成、失败。
- 搜索和过滤。
- 已连接 iPhone 状态。

设计要求：

- 左栏应紧凑，适合快速切换。
- session item 必须显示项目名、最近摘要、状态、更新时间。
- 等待用户处理的 session 应有明确高优先级视觉提示。

### 3.2 中央：Conversation / Event Stream

内容：

- 用户输入。
- assistant 输出。
- tool / command 执行状态。
- plan 结果。
- approval request。
- 文件变更摘要。
- token / usage / cost 信息。

设计要求：

- 输出流要适合长内容阅读。
- 代码块、命令、路径、diff 使用等宽字体。
- 工具执行不是裸日志，应折叠成可展开事件。
- 保留原始日志查看入口，避免隐藏底层事实。

### 3.3 右栏：Session Inspector

默认 tabs：

- Files：文件树和 session changed files。
- Diff：当前文件 diff。
- Approvals：待处理 approval。
- Settings：当前 session 配置。
- Logs：原始事件和 app-server 日志。

设计要求：

- 右栏不是全局设置页，而是当前 session 的操作面。
- diff 和 approval 要能互相跳转。
- 文件树要区分 session 前已有改动、本次 session 产生的改动、已 approve、已 staged。

### 3.4 底部：Composer + Session Toolbar

Composer 组成：

- 多行输入框。
- 发送按钮。
- 图片/文件附件入口。
- session toolbar。

Session toolbar 必须支持：

- Agent / CLI：Codex。
- Model：从 app-server model/list 动态读取。
- Reasoning effort：low、medium、high、xhigh，按模型能力展示。
- Plan mode：开关。
- Permission mode：只读、默认、完全访问。
- CWD / target Mac。
- Fast mode：按模型能力显示。

设计要求：

- 这些配置是 session 级，不是全局设置。
- 当前 session 的配置必须始终可见，尤其是模型、effort、Plan、权限。
- 完全访问需要强视觉提示，但不能让日常操作变得繁琐。

## 4. iPhone 主界面基准

推荐结构：Session List -> Session Workspace -> Detail Sheets。

### 4.1 Session List

内容：

- 当前连接的 Mac。
- Mac 在线 / 离线 / 重连中状态。
- session 列表。
- 新建 session。
- 扫码配对和设备状态。

设计要求：

- 等待处理的 session 排在前面。
- 通知点击后直接进入对应 session 和待处理项。
- 离线状态必须清楚说明原因和下一步。

### 4.2 Session Workspace

主屏内容：

- 顶部显示项目、模型、权限、Plan 状态。
- 中部显示 conversation/event stream。
- 底部输入框。
- 下方或顶部提供 Files / Diff / Approvals / Settings 快速切换。

设计要求：

- 手机端应优先暴露“当前要不要处理”的信息。
- approval、plan 执行确认、任务失败重试应以 inbox 形式出现。
- 输入不需要 Mac 二次确认；iPhone 是受信任遥控端。

### 4.3 Mobile Diff / Approval

必须支持：

- changed files 列表。
- 单文件 diff。
- approve。
- approve & stage。
- discard session changes。
- discard all file changes。
- approval request accept / reject。

设计要求：

- diff 阅读优先纵向滚动。
- 单文件操作固定在底部 action bar。
- discard all file changes 必须二次确认，最好要求本机生物识别。
- 锁屏通知默认不展示敏感代码和路径。

## 5. 状态模型

每个 session 至少需要这些 UI 状态：

- idle：未运行。
- running：正在执行。
- streaming：正在输出。
- waitingInput：等待用户输入。
- waitingApproval：等待 approval。
- waitingPlanDecision：Plan mode 输出后等待是否执行。
- failed：失败。
- completed：完成。
- stopped：被用户终止。
- disconnected：Mac 不可达或 relay 断线。

每个 connected device 至少需要这些 UI 状态：

- paired。
- online。
- reconnecting。
- offline。
- revoked。

每个 file change 至少需要这些 UI 状态：

- unchanged。
- modifiedBeforeSession。
- modifiedBySession。
- approved。
- staged。
- discarded。
- conflict。

## 6. 首版视觉方向

建议：

- 使用 Apple 平台原生视觉语言，但信息密度向 Hermes / Lody 靠拢。
- 使用系统字体 + 优秀等宽字体。
- 颜色以中性色为基础，用少量状态色表达风险和进度。
- icon 使用 SF Symbols。
- macOS 保持紧凑工具型界面，iPhone 保持清晰任务流。
- 8px 左右圆角即可，不使用过度圆润的营销风。
- 对代码、diff、终端输出优先接近 VS Code 的阅读体验。

避免：

- 首页式大 hero。
- 聊天软件式空泛气泡。
- 大面积单一色系。
- 卡片套卡片。
- 隐藏当前模型、权限、目录等关键上下文。
- 把移动端做成只读监控面板。

## 7. M1 UI 验收标准

Mac：

- 打开 App 后 10 秒内能理解当前有哪些 session、哪个在等我、在哪个项目、以什么权限运行。
- 能在不打开设置页的情况下切换模型、effort、Plan mode、权限模式。
- 能看到当前 session 的文件变化和 diff。
- 能处理 approval。
- 能查看 iPhone 是否在线和是否接管。

iPhone：

- 打开 App 后直接看到需要处理的 session。
- 能完整发起新 session、选择目录、发送输入、看输出、看 diff、处理 approval、终止 session。
- 能清楚知道 Mac 是否在线，断线后是否在重连。
- 高风险动作有足够清晰的确认。

共同：

- session 级配置双端实时同步。
- diff、approval、状态在双端看到的是同一份事实。
- UI 不让用户误以为文件和凭证已经同步到云端。

## 实现状态 vs 设计基准

### macOS Shell 当前布局

```
┌──────────────┬──────────────────────────┬──────────────┐
│  Sidebar     │  ChatWorkspace           │  Inspector   │
│  (292pt)     │  (flex)                  │  (360pt,     │
│              │                          │   ScrollView)│
│  - Session   │  ┌──────────────────┐   │  Changed F.  │
│  - Files     │  │  Message List     │   │  Diff Prev.  │
│  - Active    │  │  (scrollable)     │   │  Session     │
│    Sessions  │  └──────────────────┘   │  Codex Runt. │
│              │  ┌──────────────────┐   │  Mac Relay   │
│              │  │  Input           │   │  ├ PAIRING   │
│              │  │  (macOS 14+      │   │  ├ Status    │
│              │  │   TextField)     │   │  Mock Commds │
│              │  └──────────────────┘   └──────────────┘
└──────────────┴──────────────────────────┘
```

### iOS 当前页面结构

```
TabView {
  PairingView         — 输入 URI / 扫 QR / Claim & Connect
  ConnectionStatusView — 连接状态 / 心跳 / 重连
  SessionSnapshotView  — 当前 session 摘要
  EventReplayListView  — 事件回放列表
}
```

### 与设计基准的主要差异

| 设计基准指向 | 当前实现 | 说明 |
|------------|---------|------|
| Electron + React | SwiftUI + macOS native | 更轻量，无 Electron 开销 |
| 左侧导航 + 中央工作区 | HStack(Sidebar + Chat + Inspector) | 三栏布局，已实现底部输入 |
| 底部 slash command 菜单 | 暂无 | 当前只支持纯文本输入 |
| streaming chat UI | 支持（mock + real mode） | 已实现 Codex app-server 桥接 |
| markdown rendering | 基础 | 后续需加强 |
| iOS 原生体验 | TabView + NavigationStack | 已实现
