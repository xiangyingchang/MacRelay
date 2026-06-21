# AI 编程 CLI 客户端 Mac Relay 技术设计

创建日期：2026-06-21

关联文档：

- [[AI 编程 CLI 客户端需求文档]]
- [[AI 编程 CLI 客户端落地执行计划]]
- [[AI 编程 CLI 客户端 UI 设计基准]]

## 1. 设计目标

Mac Relay 是整个产品的核心运行层。

它不是简单的网络转发器，而是 Mac 本地 Codex session 的控制中心：

- 连接并管理 `codex app-server`。
- 把 Codex app-server 的 JSON-RPC 事件归一化为客户端状态。
- 向 Mac UI 和 iPhone UI 广播同一份 session 状态。
- 接收 Mac / iPhone 的控制命令，并映射回 Codex app-server。
- 维护配对设备、鉴权、heartbeat、断线恢复、事件重放。
- 保证所有执行、文件访问、凭证和 Codex 登录态都留在 Mac。

第一版只支持局域网直连，不做云端 relay。

## 2. 已验证基础

M0 已验证：

- `codex app-server --stdio` 可用。
- Swift 版探针可直接通过 `Process` + `Pipe` 连接 `codex app-server --stdio`。
- `codex app-server --stdio` 当前可按 newline-delimited JSON 读取。
- 可通过 JSON-RPC 完成 `initialize`、`model/list`、`thread/start`、`turn/start`。
- 可通过 `thread/settings/update` 更新 session 级模型、effort、approval policy、sandbox。
- 可接收 assistant streaming、status changed、settings updated、token usage。
- 可接收 `turn/diff/updated` 和 `fileChange` item。
- read-only sandbox 下可触发 approval request。
- 客户端可响应 approval request 并让 Codex 继续执行。
- 临时 Node relay 已跑通：
  - `startThread`
  - `sendTurn`
  - `updateSettings`
  - `resolveApproval`
  - SSE 状态广播

因此正式工程应优先走 app-server 协议路线，PTY 只作为其他 CLI 或 app-server 不足时的 fallback。

## 3. 进程边界

### 3.1 Mac App

职责：

- 提供 SwiftUI / AppKit UI。
- 启动和持有 Mac Relay。
- 管理菜单栏常驻、防休眠、本地通知、设备管理。
- 通过进程内 API 订阅 Relay 状态。

### 3.2 Mac Relay

职责：

- 作为 Mac App 内部服务运行。
- 管理 app-server 子进程。
- 管理局域网监听服务。
- 管理 session registry。
- 管理设备连接和协议状态。

实现形式：

- M1 推荐先做为 Mac App 进程内 Swift actor / service。
- 后续如需“App UI 退出后 relay 仍运行”，再拆为 LaunchAgent / helper daemon。
- 第一版可以做到关闭主窗口不退出 App，菜单栏保持 relay 运行。

### 3.3 Codex app-server

职责：

- 真正执行 Codex session。
- 持有 Codex 原生 thread / turn / approval / diff 状态。
- 读写 `~/.codex` 本地状态。

启动方式：

- `codex app-server --stdio`

不建议第一版直接暴露 `codex app-server --listen ws://0.0.0.0:<port>` 给局域网。

原因：

- iPhone 不应直接理解 Codex app-server 的完整协议。
- app-server 可能暴露过多底层能力。
- Relay 需要做设备鉴权、事件归一化、权限收敛和兼容层。

## 4. Swift 模块拆分

建议共用 Swift Package：`AgentClientCore`。

### 4.1 Shared Core

模块：

- `SessionModel`
- `CodexSettingsModel`
- `RelayProtocol`
- `PairingModel`
- `DiffModel`
- `ApprovalModel`
- `DeviceModel`
- `EventStore`

使用方：

- macOS App
- iPhone App
- 单元测试

### 4.2 macOS App Modules

- `CodexAppServerClient`
- `MacRelayServer`
- `PairingServer`
- `DeviceTrustStore`
- `SessionRegistry`
- `SessionStateReducer`
- `FileBrowserService`
- `DiffManager`
- `SleepPreventionManager`
- `NotificationRouter`
- `MenuBarController`
- `MacUIShell`

### 4.3 iPhone App Modules

- `PairingScanner`
- `RelayClient`
- `SessionStore`
- `SessionWorkspace`
- `MobileDiffViewer`
- `ApprovalInbox`
- `ProjectBrowser`
- `MobileSettingsPanel`
- `ConnectionSupervisor`

## 5. Relay 内部数据流

### 5.1 下行：Codex -> Relay -> UI

1. `CodexAppServerClient` 从 stdio 读取 JSON-RPC message。
2. 解析为 Codex 原始事件。
3. `SessionStateReducer` 将原始事件归一化为产品状态。
4. `EventStore` 写入事件序列。
5. `SessionRegistry` 更新当前 session snapshot。
6. `MacRelayServer` 广播事件给 iPhone。
7. Mac UI 直接订阅同一份状态。

### 5.2 上行：UI -> Relay -> Codex

1. Mac UI 或 iPhone 发送 command。
2. Relay 验证设备、session、权限和 command schema。
3. command 被映射为 app-server JSON-RPC request / notification。
4. Relay 记录 command event。
5. Codex app-server 返回 response 或后续 notification。
6. Relay 更新状态并广播。

## 6. 移动端协议

第一版推荐 WebSocket + JSON。

Node 探针阶段用 HTTP + SSE 已验证可行，但正式移动端需要双向低延迟通信、heartbeat、重连和 command response correlation，WebSocket 更合适。

### 6.1 连接地址

二维码内容建议包含：

```json
{
  "scheme": "agentclient",
  "version": 1,
  "host": "192.168.1.23",
  "port": 48731,
  "pairingToken": "one-time-token",
  "macName": "Haoshi MacBook",
  "relayPublicKey": "base64-public-key"
}
```

### 6.2 Message Envelope

所有消息使用统一 envelope：

```json
{
  "id": "uuid",
  "type": "session.command",
  "version": 1,
  "timestamp": "2026-06-21T00:00:00Z",
  "payload": {}
}
```

字段：

- `id`：用于 command response correlation。
- `type`：事件或命令类型。
- `version`：协议版本。
- `timestamp`：发送方时间，用于调试，不作为可信排序依据。
- `payload`：业务内容。

Relay 内部事件排序以 server sequence 为准。

### 6.3 Commands

M1 必须支持：

- `pairing.claim`
- `session.list`
- `session.start`
- `session.stop`
- `session.turn.start`
- `session.settings.update`
- `approval.resolve`
- `project.browse`
- `diff.list`
- `diff.get`
- `diff.approve`
- `diff.stage`
- `diff.discardSessionChanges`
- `diff.discardAllFileChanges`
- `device.revoke`
- `heartbeat.ping`

### 6.4 Events

M1 必须支持：

- `connection.ready`
- `connection.heartbeat`
- `session.snapshot`
- `session.started`
- `session.status.changed`
- `session.settings.updated`
- `turn.started`
- `turn.delta`
- `turn.completed`
- `turn.failed`
- `diff.updated`
- `fileChange.updated`
- `approval.requested`
- `approval.resolved`
- `project.browse.result`
- `device.revoked`
- `error`

### 6.5 Snapshot + Replay

连接建立后不只推事件流，必须先发 snapshot：

```json
{
  "type": "session.snapshot",
  "payload": {
    "sessions": [],
    "activeSessionId": "...",
    "pendingApprovals": [],
    "lastEventSeq": 123
  }
}
```

断线重连时：

- iPhone 带上 `lastSeenEventSeq`。
- Relay 如果仍有事件缓存，则 replay 缺失事件。
- 如果事件缓存不足，则重新发送完整 snapshot。

第一版事件缓存建议：

- 每个 session 保留最近 1000 条归一化事件。
- 全局保留最近 24 小时事件。
- 长期历史另存 SQLite。

## 7. 状态模型

### 7.1 Session Snapshot

```json
{
  "id": "session-id",
  "tool": "codex",
  "projectPath": "/Users/name/project",
  "title": "Fix CI failure",
  "status": "running",
  "createdAt": "...",
  "updatedAt": "...",
  "settings": {},
  "pendingApprovalIds": [],
  "changedFileCount": 0,
  "connectedDevices": []
}
```

### 7.2 Session Status

状态枚举：

- `idle`
- `running`
- `streaming`
- `waitingInput`
- `waitingApproval`
- `waitingPlanDecision`
- `completed`
- `failed`
- `stopped`
- `disconnected`

### 7.3 Codex Settings

```json
{
  "model": "gpt-5.4-mini",
  "effort": "medium",
  "planMode": false,
  "approvalPolicy": "on-request",
  "sandbox": {
    "type": "workspaceWrite"
  },
  "permissionMode": "default",
  "profile": null,
  "webSearch": "cached",
  "serviceTier": null,
  "personality": null,
  "cwd": "/Users/name/project"
}
```

UI 展示优先使用产品化字段：

- `permissionMode = readOnly | default | fullAccess`

底层映射：

- `readOnly` -> `approvalPolicy = on-request` 或 `never` + `sandbox.type = readOnly`
- `default` -> `approvalPolicy = on-request` + `sandbox.type = workspaceWrite`
- `fullAccess` -> `approvalPolicy = never` + `sandbox.type = dangerFullAccess`

具体映射要以 app-server schema 和实际验证结果为准。

## 8. Approval 路由

Relay 需要保存 pending approval：

```json
{
  "id": "approval-id",
  "sessionId": "session-id",
  "turnId": "turn-id",
  "kind": "commandExecution",
  "title": "Run command",
  "reason": "...",
  "availableDecisions": ["accept", "reject"],
  "createdAt": "...",
  "expiresAt": null,
  "rawRequestId": "json-rpc-id",
  "rawPayload": {}
}
```

流程：

1. app-server 发出 server request。
2. Relay 生成 `approval.requested`。
3. Mac UI / iPhone UI 都展示同一条 pending approval。
4. 任一端选择 accept / reject。
5. Relay 只允许第一次有效响应。
6. Relay 对 app-server 原始 request id 返回 JSON-RPC response。
7. Relay 广播 `approval.resolved`。

需要处理：

- 两端同时响应。
- 设备断线后重新看到 pending approval。
- app-server request 超时或 turn 被终止。
- raw request 类型未来增加。

## 9. Diff 与文件变更

第一版采用双层策略：

- 优先使用 app-server 的 `turn/diff/updated` 和 `fileChange` item。
- Git working tree diff 作为校验和 fallback。

Relay 对 UI 暴露统一模型：

```json
{
  "fileId": "stable-file-id",
  "path": "src/App.swift",
  "absolutePath": "/Users/name/project/src/App.swift",
  "changeKind": "modified",
  "source": "appServer",
  "reviewStatus": "unreviewed",
  "stageStatus": "unstaged",
  "diff": "..."
}
```

操作：

- `diff.approve`：只更新客户端 review status，不执行 Git。
- `diff.stage`：执行 `git add <file>`。
- `diff.discardSessionChanges`：只回滚 session 产生的变更，保留 session 前已有改动。
- `diff.discardAllFileChanges`：恢复到 Git HEAD 或明确 baseline，高风险。

`discardSessionChanges` 是 M1 的难点，必须依赖 session baseline：

- session start 时记录文件 hash / git diff baseline。
- Codex 修改后计算当前 diff。
- 回滚时只反向应用本次 session 的 patch。
- 如果 patch 无法干净应用，进入 conflict 状态，不自动破坏用户文件。

## 10. Pairing 与设备信任

### 10.1 首次配对

流程：

1. Mac 生成一次性 pairing token。
2. Mac 生成 relay key pair。
3. 二维码包含地址、端口、token、relay public key。
4. iPhone 连接 WebSocket，发送 `pairing.claim`。
5. Relay 校验 token。
6. iPhone 生成 device key pair，并发送 device public key、设备名。
7. Relay 生成 device id，写入 macOS Keychain。
8. iPhone 保存 device credential 到 iOS Keychain。
9. 配对完成后 token 失效。

### 10.2 后续重连

- iPhone 使用 device id + signed nonce 重连。
- Relay 校验签名和吊销状态。
- 成功后发送 snapshot。

### 10.3 吊销

- Mac 端可吊销设备。
- iPhone 端可退出配对。
- 吊销后所有连接立即断开。
- Relay 拒绝该 device id 后续重连。

## 11. 局域网发现

第一版建议：

- 二维码直连为主。
- Bonjour / Network framework 作为增强。

需要处理：

- macOS 本地网络权限。
- iOS 本地网络权限。
- 防火墙提示。
- IP 变化。
- Mac 锁屏或网络切换。

连接失败时，iPhone UI 应清楚区分：

- 不在同一局域网。
- Mac App 未运行。
- Mac 防火墙阻止。
- 配对凭证失效。
- 设备已被吊销。

## 12. 安全边界

Relay 必须保证：

- 不向 iPhone 发送 API key、SSH key、Git 凭证、Codex auth token。
- 不把 conversation、diff、文件内容上传自有服务器。
- iPhone 所有高权限操作都在 Mac 本机执行。
- 移动端浏览用户目录时，默认隐藏或警告敏感目录。

建议默认敏感目录：

- `~/.ssh`
- `~/.gnupg`
- `~/Library/Keychains`
- 浏览器 profile 目录
- 密码管理器数据目录
- `~/.codex` 中的敏感配置和 token 文件

注意：

- 用户明确选择项目目录时，可以访问项目文件。
- 对隐藏敏感目录的策略要可配置，但默认应保守。

## 13. 防休眠

Relay 与 SleepPreventionManager 的关系：

- 有运行中的 session 且用户开启“运行 session 时禁止休眠”时，申请防休眠。
- 有 iPhone 在线且用户开启“连接 iPhone 时禁止休眠”时，申请防休眠。
- 所有条件解除后释放。
- App 退出前必须释放。

UI 必须显示当前防休眠原因。

## 14. 错误处理

错误分层：

- `codexUnavailable`：找不到 Codex CLI。
- `appServerFailed`：app-server 启动或协议失败。
- `sessionFailed`：session / turn 失败。
- `approvalFailed`：approval 响应失败或过期。
- `networkUnavailable`：局域网服务不可用。
- `deviceUnauthorized`：设备未授权或被吊销。
- `fileOperationFailed`：diff / stage / discard 失败。
- `permissionRequiredOnMac`：需要 Mac 本机授权。

iPhone 端必须把 `permissionRequiredOnMac` 显示为“需要回到 Mac 处理”，不要伪装成可在手机解决。

## 15. M1 实现顺序

建议顺序：

1. 建立 Swift Package 和共享模型。
2. 实现 `CodexAppServerClient`，复刻 Node 探针能力。
3. 实现 `SessionStateReducer` 和 `SessionRegistry`。
4. 实现 Mac App 内本机 UI 订阅状态，不先做 iPhone。
5. 实现 WebSocket server 和本机模拟 client。
6. 实现二维码 pairing 和 device trust。
7. 实现 iPhone WebSocket client。
8. 实现 session list / workspace / composer。
9. 实现 approval inbox。
10. 实现 diff viewer 和单文件操作。
11. 实现断线重连、snapshot、event replay。
12. 实现防休眠和菜单栏常驻。

## 16. M1 最小可用验收

必须做到：

- Mac App 启动后能检测 Codex。
- Mac App 能启动 app-server 并发起 session。
- Mac UI 能看到 streaming 输出。
- Mac UI 能切换 session 级模型、effort、权限模式。
- iPhone 能扫码连接 Mac。
- iPhone 能看到 session snapshot 和后续事件。
- iPhone 能发送 turn。
- iPhone 能处理至少一种 approval。
- iPhone 能看到 diff。
- iPhone 断线后能恢复当前 session 状态。
- Mac 菜单栏保持 relay 运行。
- 防休眠配置生效。

暂不要求：

- 多 CLI adapter。
- 云端中继。
- 完整历史搜索。
- 团队协作。
- App Store 分发。
