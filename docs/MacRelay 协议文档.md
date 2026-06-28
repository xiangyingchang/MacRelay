# MacRelay 协议文档

创建日期：2026-06-23  | 最后更新：2026-06-28
协议版本：1
对应 HEAD：`34e83a8`（未提交改动含 AgentRuntime 架构、Claude Code 支持）

## 概述

MacRelay 是 Mac 本地的 relay 服务，将 Codex app-server 的 session 状态通过 HTTP 和 WebSocket 暴露给同一局域网内的 iPhone 客户端。

- HTTP 提供 query 和 pairing 端点
- WebSocket 提供双向实时命令/事件通道
- 两者通过 `wsPort` 字段关联（见配对 payload）
- 共享同一个 `MacRelayService` 事件状态

## 部署形态

### macOS 端

```bash
# 开发/调试（裸 Mach-O）
cd /private/tmp/MacRelay && swift build && open .build/debug/AgentClientMacShell

# 正式运行（.app bundle，输入法 / Text Services 正常工作）
scripts/build-mac-shell-app.sh
open .build/AgentClientMacShell.app
```

`.app` bundle 由 `scripts/build-mac-shell-app.sh` 自动生成 + ad-hoc codesign。

### iOS 端

```bash
# Simulator（SwiftPM CLI）
scripts/build-ios.sh

# 真机（必须 Xcode codesign）
open Apps/MacRelayiOSApp/MacRelayiOSApp.xcodeproj
# → 选 MacRelayiOSApp scheme → iPhone → Personal Team → ⌘R
```

真机必须通过 Xcode 项目签名，SwiftPM 产生的 unsigned Mach-O 无法安装到真实设备。

## HTTP Endpoints

默认监听 `127.0.0.1`（Localhost 模式）或自动发现的 LAN IP（LAN 模式）。端口随机分配。

### `GET /pairing`

返回当前配对 payload（无需 auth）：

```json
{
  "host": "192.168.1.5",
  "port": 63165,
  "wsPort": 48732,
  "token": "uuid-token",
  "claim": "uuid-claim",
  "protocolVersion": 1,
  "expiresAt": "2026-06-23T00:10:00Z",
  "claimedAt": null,
  "deviceID": "uuid-device",
  "deviceSecret": null
}
```

关键字段：
- `token`：会话级授权 token
- `claim`：一次性声明令牌（用于 `/pairing/claim`）
- `wsPort`：WebSocket 服务器端口（与 HTTP 端口不同）
- `expiresAt`：token 过期时间
- `claimedAt`：null 表示尚未被 claim
- `deviceSecret`：**始终为 null**。deviceSecret 仅通过 claim 响应下发，不暴露在无须 auth 的 GET /pairing 中

### `GET /pairing/claim?claim=<uuid-claim>`

一次性 claim。调用成功后：
- `claimedAt` 设为首次调用时间
- 后续同一 claim 再调用返回 `409 Conflict`
- 成功后返回完整 pairing payload（含 claimedAt + deviceID + deviceSecret）

返回 `401` 情况：
- claim 不匹配
- token 已过期

### `GET /snapshot?token=<token>`

返回当前 relay snapshot（需 token auth）：

```json
{
  "type": "session.snapshot",
  "seq": 4,
  "payload": {
    "activeSessionID": "...",
    "session": { ... },
    "connection": { ... },
    "pendingApprovals": [],
    "lastEventSeq": 4
  }
}
```

### `GET /replay?afterSeq=<n>&maxEvents=<m>&token=<token>`

返回缺失事件：

```json
{
  "kind": "events",
  "reason": null,
  "events": [ ... ]
}
```

若缓存不足，返回 `kind: "needsFullSnapshot"`，客户端应改调 `/snapshot`。

## Short URI 格式

扫码/手动输入的配对 URI 格式：

```
macrelay://pair?host=<IP>&port=<HTTP-port>&claim=<UUID>
```

生成（`RelayPairingURI`）：

```swift
var c = URLComponents()
c.scheme = "macrelay"
c.host = "pair"
c.queryItems = [
    URLQueryItem(name: "host", value: host),
    URLQueryItem(name: "port", value: "\(port)"),
    URLQueryItem(name: "claim", value: claim)
]
```

解析（`RelayPairingURI.detect()`）：
1. 尝试解析为 short URI
2. 若失败，退化为 JSON payload backward compatibility

URI 中**不包含 `deviceSecret`**。deviceSecret 仅通过 claim HTTP 响应下发。

## Auth Flow

### HTTP Auth

每个需要授权的端点通过 `?token=<token>` 传入。
无 token 或 token 无效 → `401 Unauthorized`。

### WebSocket Auth（Token 方式）

WebSocket 连接建立后（连接到 `ws://<host>:<wsPort>/relay`），第一条消息必须是：

```json
{
  "type": "mac-relay.authorize",
  "payload": { "token": "<pairing-token>" }
}
```

- 成功 → 返回 `{"type": "mac-relay.authenticated", "payload": {"status": "ok"}}`
- 失败 → 返回 `{"type": "error", "payload": {"error": "..."}}` 并关闭连接

### WebSocket Auth（Challenge-Response 方式）

在 DeviceTrustStore 注册后，可以使用 device credential 认证：

1. 客户端发送：
```json
{"type": "mac-relay.authorize", "payload": {"deviceId": "<deviceID>"}}
```
2. 服务器回复：
```json
{"type": "mac-relay.challenge", "payload": {"nonce": "<random-hex>"}}
```
3. 客户端计算 HMAC-SHA256(nonce, deviceSecret) 并回复：
```json
{"type": "mac-relay.authorize", "payload": {"deviceId": "<deviceID>", "challengeResponse": "<hmac>"}}
```
4. 服务器验证签名 → `mac-relay.authenticated` 或 `error`

## WebSocket Message Envelope

所有消息使用统一 JSON envelope：

```json
{
  "id": "uuid",
  "type": "session.command",
  "version": 1,
  "seq": 123,
  "correlationID": "...",
  "timestamp": "2026-06-23T00:00:00Z",
  "payload": { }
}
```

### Commands

| type | direction | 说明 |
|------|-----------|------|
| `snapshot.get` | client → server | 请求当前 session snapshot |
| `replay.from` | client → server | 重放缺失事件 |
| `heartbeat.ping` | client → server | 心跳检测 |
| `session.list` | client → server | 获取所有 session 列表 |
| `session.start` | client → server | 创建新 session（可带 initialPrompt） |
| `session.stop` | client → server | 停止当前 session |
| `session.select` | client → server | 切换当前选中的 session（仅更新元数据，不重建 thread） |
| `session.turn.start` | client → server | 发送用户消息 |
| `session.settings.update` | client → server | 更新 model/effort/planMode/权限 |
| `approval.resolve` | client → server | 审批 accept/reject |
| `mac-relay.authorize` | client → server | 认证（token 或 challenge-response） |

### Events (server → client)

| type | 说明 |
|------|------|
| `session.snapshot` | snapshot response |
| `mac-relay.authenticated` | auth 成功 |
| `mac-relay.challenge` | challenge 响应 |
| `session.started` | 新 session 开始 |
| `session.status.changed` | session 状态变更 |
| `session.settings.updated` | session 设置变更 |
| `turn.started` | turn 开始 |
| `turn.delta` | assistant streaming delta |
| `turn.completed` | turn 完成 |
| `diff.updated` | diff 变更 |
| `fileChange.updated` | 文件变更 |
| `approval.requested` | 审批请求 |
| `approval.resolved` | 审批解决 |
| `connection.heartbeat` | heartbeat response |
| `error` | 错误 |

### Error Envelope

```json
{
  "type": "error",
  "payload": { "error": "描述信息" }
}
```

## Pairing Flow（完整）

```
┌─ Mac Shell ─┐                    ┌─ iPhone ─┐
│ Start relay │                    │          │
│ HTTP + WS   │                    │          │
│             │                    │ Scan QR  │
│             │←— GET /pairing ——│ 解析 URI  │
│ 返回 payload│                    │          │
│ (含 wsPort) │                    │          │
│             │← claim?claim=X ——│          │
│ 返回 token  │                    │  Save     │
│ + deviceID  │                    │ creds    │
│ + deviceSec │                    │          │
│             │←— WS connect ———→│          │
│             │  (wsPort)         │          │
│             │← authorize(token)│          │
│ authenticate│                    │          │
│> connected >│                    │          │
│             │← snapshot.get ——│          │
│             │→ session.snap —→│          │
│             │← heartbeat.ping │          │
│             │→ conn.heartbeat →│          │
└─────────────┘                    └──────────┘
```

## iPhone 客户端接入

1. 扫描 Mac 上显示的 QR 码（或粘贴 `macrelay://pair?...` URI）
2. `RelayHTTPClient` 调用 `GET /pairing/claim?claim=...`
3. 从 claim 响应获取 `token` 和 `wsPort`
4. 连接 WebSocket：`ws://<host>:<wsPort>/relay`
5. `wsClient.authenticate(token:)`
6. 收到 `mac-relay.authenticated` 后：
   - 调用 `snapshot.get` 获取当前完整状态
   - 开始监听事件或发送后续命令
7. 定期发送 `heartbeat.ping` 保持连接
8. 断线后自动重连（指数退避）

## 当前实现状态

- ✅ HTTP claim + 409 防重放
- ✅ WebSocket token auth
- ✅ WebSocket challenge-response (HMAC-SHA256)
- ✅ DeviceTrustStore（memory + Keychain）
- ✅ Keychain credential persistence
- ✅ 连接状态机（MobileConnectionStateMachine）
- ✅ 心跳 + 指数退避重连
- ✅ macrelay:// short URI
- ✅ LAN IP 自动发现
- ✅ Localhost / LAN 切换
- ✅ `.app` bundle（输入法正常工作）
- ✅ Xcode project for iOS 真机签名
- ✅ ATS（NSAllowsLocalNetworking）
- ✅ 真机 QR 扫码
- ✅ session.list / session.start / session.stop / session.select 命令
- ✅ session title 从首条用户消息自动命名（~6字截断）
- ✅ push broadcast 含 availableSessions
- ✅ snapshot.get 现在也返回 availableSessions（注入 runtime.sessions）
- ✅ iOS 端 session 列表筛选/搜索
- ✅ iOS 端创建/切换 session
- ✅ 双端消息双向同步（Mac → iOS、iOS → Mac）
- ✅ 新建 session 清空历史对话（reducer threadStarted 清 turns）
- ✅ Mock 模式完全移除
- ✅ Mac 侧边栏折叠功能（Hermes Desktop 风格窄条）
- ⏳ 断线重连后状态机一致性验证
- ⏳ Bonjour 局域网发现
- ⏳ 统一协议错误码枚举
- ⏳ 常驻能力（菜单栏、后台运行）
- ⏳ 防休眠配置
