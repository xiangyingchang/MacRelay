# AI 编程 CLI 客户端 iPhone 信息架构

创建日期：2026-06-21

关联文档：

- [[AI 编程 CLI 客户端需求文档]]
- [[AI 编程 CLI 客户端 UI 设计基准]]
- [[AI 编程 CLI 客户端落地执行计划]]
- [[AI 编程 CLI 客户端 Mac Relay 技术设计]]

## 1. 设计目标

iPhone 端不是 Mac 客户端的只读通知面板，也不是桌面端缩小版。它的目标是：在 Mac 继续负责执行 Codex CLI、访问文件、使用本地凭证的前提下，让用户在手机上完整接手 session 的观察、输入、配置、审批、diff review 和文件决策。

核心原则：

- Mac 是唯一执行端和数据源。
- iPhone 是受信任远程操作端。
- iPhone 输入不需要 Mac 二次确认。
- iPhone 不直接获得 Mac 的 API key、SSH key、Git 凭证。
- 所有敏感执行仍发生在 Mac 本机。
- 第一版只支持局域网直连。
- 操作围绕 session 组织，而不是围绕全局设置组织。

## 2. 一级信息架构

iPhone App 使用 4 个主要区域：

1. **Sessions**
   - 默认首页。
   - 展示当前 Mac、连接状态、需要处理的 session、运行中的 session、最近 session。
2. **Inbox**
   - 聚合所有需要用户处理的阻塞点。
   - 包括 approval、Plan 决策、失败重试、Mac-only 授权提示、断线提醒。
3. **Files**
   - 当前选中 session 的文件变更和 diff 入口。
   - 如果没有选中 session，则展示最近有变更的 session 列表。
4. **Devices**
   - Mac 连接状态、配对、重连、吊销、本机生物识别策略。

底部 tab 建议：

- `Sessions`
- `Inbox`
- `Files`
- `Devices`

不建议把 Settings 做成一级 tab。全局设置第一版可以藏在 Devices 或 Sessions 顶部菜单里；高频配置应该留在 session workspace 内。

## 3. Sessions 首页

### 3.1 顶部 Mac 状态

首页顶部必须一眼说明：

- 当前连接的 Mac 名称。
- 连接方式：LAN。
- 在线状态：online / reconnecting / offline。
- Mac 是否阻止休眠。
- 当前 iPhone 是否已被授权接管。

示例信息：

- `Haoshi's MacBook Pro`
- `LAN · Online`
- `Sleep prevented while connected`

状态优先级：

1. Mac offline / reconnecting
2. 有等待处理的 approval / Plan
3. 有正在运行的 session
4. 普通最近 session

### 3.2 Session 列表分组

Session 列表按操作优先级分组：

1. **Needs Attention**
   - waitingApproval
   - waitingPlanDecision
   - failed
   - Mac-only authorization required
2. **Running**
   - running
   - streaming
3. **Recent**
   - completed
   - stopped
   - idle

每个 session item 必须显示：

- 项目名或目录名。
- 最近摘要。
- 当前 agent：Codex。
- 当前状态。
- 模型。
- 权限模式。
- 是否有文件变更。
- 是否有待处理项。
- 最近更新时间。

session item 上不展示长路径；点击后在 workspace header 或 project sheet 中展示完整路径。

### 3.3 首页主操作

首页顶部或底部浮动按钮：

- New Session

New Session 流程：

1. 选择 Mac。
2. 选择项目目录。
3. 选择 Codex 配置：
   - model
   - effort
   - Plan mode
   - permission mode
4. 输入初始 prompt。
5. Start。

目录选择必须允许浏览 Mac 当前用户可访问的整个用户目录，但敏感目录要有风险提示。

## 4. Session Workspace

Session Workspace 是 iPhone 端最核心页面。

推荐结构：

- 顶部：Session Header
- 中部：Conversation / Event Stream
- 底部：Composer
- 右上或底部：Session Tools

### 4.1 Session Header

Header 必须持续显示：

- 项目名。
- session 状态。
- 当前模型。
- effort。
- Plan mode。
- permission mode。
- Mac 在线状态。

Header 可折叠。折叠时只保留：

- 项目名
- 状态 pill
- 权限风险标识

点击 Header 打开 Session Settings Sheet。

### 4.2 Conversation / Event Stream

内容类型：

- user message
- assistant output
- tool / command event
- approval event
- Plan decision event
- diff summary event
- error event

移动端不应展示裸日志洪流。默认展示结构化事件，保留“View Raw Log”入口。

消息流规则：

- 当前 turn 的 streaming 状态必须可见。
- 历史 turn 静态展示。
- command event 默认折叠，展示命令名、状态、耗时。
- 失败 event 必须给出可执行动作：retry、copy、view log。
- approval event 必须可直接操作，不强迫用户切换页面。

### 4.3 Bottom Composer

Composer 固定在底部：

- 多行输入。
- Send / Stop。
- 附件入口。
- Session Toolbar 入口。

Composer 不需要 Mac 二次确认。

输入行为：

- Return 换行。
- Send 按钮发送。
- 支持粘贴文本和图片。
- 如果当前 session 已停止，输入框变为 `Resume session` 或 `Start follow-up`。

### 4.4 Session Tools

Session tools 可以用顶部 segmented control 或底部 drawer：

- Chat
- Files
- Approvals
- Settings
- Logs

默认停留在 Chat。出现待处理 approval 时，工具入口显示 badge。

## 5. Inbox

Inbox 是所有阻塞点的聚合入口。

### 5.1 Inbox item 类型

1. **Command Approval**
   - Codex 请求执行命令。
   - 展示命令、cwd、原因、风险。
   - 操作：Approve / Reject。
2. **Plan Decision**
   - Codex 输出计划，等待执行确认。
   - 操作：Run Plan / Edit Prompt / Reject。
3. **File Review**
   - session 产生文件变更，等待 review。
   - 操作：Open Diff / Approve File / Discard。
4. **Failure**
   - 任务失败或命令失败。
   - 操作：Retry / Ask Codex to fix / View Log。
5. **Mac-only Authorization**
   - Codex 登录、Git credential、OAuth、系统权限等只能在 Mac 上完成。
   - 操作：Show on Mac / Mark handled / Retry。
6. **Connection**
   - Mac offline、reconnecting、device revoked。
   - 操作：Reconnect / Pair Again / View Device。

### 5.2 Inbox 排序

排序规则：

1. 高风险且阻塞执行的 approval。
2. Plan decision。
3. failed session。
4. 文件 review。
5. 普通通知。

每个 item 必须显示所属 session 和项目，避免用户在错误上下文里批准操作。

## 6. Files / Diff

### 6.1 File List

File list 可从 Session Workspace 或 Files tab 进入。

每个 file row 显示：

- 文件路径，优先展示最后两级路径。
- change kind：modified / created / deleted / renamed。
- diff 统计：+ / -。
- review state：pending / approved / staged / discarded。
- 是否 session 前已有改动。

文件分组：

- Pending Review
- Approved
- Staged
- Existing Before Session
- Discarded

### 6.2 Diff Viewer

Diff viewer 采用纵向阅读优先：

- 顶部：文件路径、状态、+/-。
- 中部：unified diff 或 rendered diff。
- 底部固定 action bar：
  - Approve
  - Approve & Stage
  - Discard Session Changes
  - More

More 中放高风险动作：

- Discard All File Changes
- Open Raw Diff
- Copy Path

### 6.3 discard 语义

默认 discard 指 `discard session changes`：

- 只丢弃本次 session 产生的改动。
- 保留 session 开始前用户已有改动。

`discard all file changes` 是高风险动作：

- 恢复到 Git HEAD 或明确 baseline。
- 需要二次确认。
- 建议要求 Face ID / Touch ID。

## 7. Session Settings Sheet

从 Header 或 Composer toolbar 打开。

设置项：

- Agent：Codex。
- Model。
- Effort：low / medium / high / xhigh。
- Plan mode。
- Permission mode：
  - Read Only
  - Default
  - Full Access
- Approval policy。
- Sandbox mode。
- CWD。
- Mac。

设计规则：

- 标明哪些设置“立即生效”。
- 标明哪些设置“下个 turn 生效”。
- 如果某设置只能新 session 生效，明确提示并提供 `Start new session with this setting`。
- Full Access 切换需要风险提示。
- 高风险切换可要求本机生物识别。

## 8. Project Browser

Project Browser 用于新建 session 或切换 cwd。

能力：

- 浏览 Mac 用户目录。
- 搜索目录。
- 收藏常用项目。
- 显示最近项目。
- 显示权限错误。

敏感目录策略：

- 默认不隐藏整个用户目录。
- 对 `.ssh`、`.gnupg`、浏览器配置、密码管理器目录等展示敏感提示。
- 进入敏感目录前可要求二次确认。
- iPhone 不直接展示密钥内容，文件读取能力由 Mac Relay 控制。

## 9. Devices

Devices 页面展示：

- 已配对 Mac。
- 当前连接状态。
- 最近连接时间。
- 当前网络。
- 设备 token 状态。
- 是否允许远程控制。
- 是否启用 Face ID / Touch ID。

操作：

- Pair New Mac。
- Reconnect。
- Forget Mac。
- Require Face ID for high-risk actions。

Mac 端吊销后：

- iPhone 立即进入 revoked 状态。
- 禁止发送任何 command。
- 本地只保留非敏感历史摘要或直接清空。

## 10. 通知

通知类型：

- Approval needed。
- Plan ready。
- Session completed。
- Session failed。
- Mac disconnected。
- Mac-only authorization needed。

通知隐私：

- 默认不在锁屏展示代码、diff、完整路径。
- 可展示项目名和状态。
- 点击通知必须直达对应 session 和待处理 item。

## 11. Relay Command 映射

iPhone UI 不直接理解 Codex app-server 的完整 JSON-RPC。它只向 Mac Relay 发送规范化 command。

| iPhone 操作 | Relay command | 说明 |
|---|---|---|
| 新建 session | `session.start` | 携带 cwd、model、effort、permission、Plan 初始配置 |
| 发送输入 | `session.turn.start` | 携带 sessionId、input、turn 级覆盖配置 |
| 终止 session | `session.stop` | 停止 Mac 上对应 CLI session |
| 切换模型/effort/权限 | `session.settings.update` | 更新当前 session 后续 turn 配置 |
| Approve command | `approval.resolve` | decision = accept |
| Reject command | `approval.resolve` | decision = reject |
| 打开文件 diff | `diff.get` | 获取当前文件 diff |
| 文件 approve | `file.approve` | 客户端 review state |
| Approve & stage | `file.stage` | Mac 执行 git add |
| Discard session changes | `file.discardSessionChanges` | 只丢弃本 session 改动 |
| Discard all file changes | `file.discardAllChanges` | 高风险，需二次确认 |
| 浏览目录 | `project.browse` | Mac 返回目录项 |
| 断线恢复 | `replay.from` | 携带 lastSeenSeq |
| 获取完整状态 | `snapshot.get` | 返回 session snapshot |

## 12. 首版页面清单

MVP 必做：

- Pairing Scan。
- Sessions Home。
- New Session。
- Project Browser。
- Session Workspace。
- Session Settings Sheet。
- Inbox。
- File List。
- Diff Viewer。
- Devices。

可后置：

- 全局历史搜索。
- 跨 Mac 多设备管理。
- 文件内容浏览器。
- 高级日志查询。
- 通知规则配置。
- 多 runtime 切换页面。

## 13. 成功标准

iPhone 首版可用的最低标准：

- 打开 App 后 10 秒内知道 Mac 是否在线。
- 打开 App 后 10 秒内知道哪个 session 在等我。
- 能进入 session 查看输出并发送输入。
- 能切换 model / effort / Plan / permission。
- 能看到文件变更和 diff。
- 能 approve / reject command approval。
- 能 approve / stage / discard 单文件变更。
- 能新建 session 并选择项目目录。
- 能终止 session。
- 断线重连后能恢复最近状态。
