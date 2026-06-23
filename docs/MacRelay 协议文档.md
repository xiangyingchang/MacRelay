# MacRelay 协议文档

创建日期：2026-06-23  
协议版本：1  
对应 HEAD：可运行 `git rev-parse --short HEAD` 查看

## 概述

MacRelay 是 Mac 本地的 relay 服务，将 Codex app-server 的 session 状态通过 HTTP 和 WebSocket 暴露给同一局域网内的 iPhone 客户端。

- HTTP 提供 query 和 pairing 端点
- WebSocket 提供双向实时命令/事件通道
- 两者共享同一个 `MacRelayService` 事件状态

## HTTP Endpoints

默认只监听 `127.0.0.1`。端口可配置。

### `GET /pairing`

返回当前配对 payload（无需 auth）：

```json
{
  "host": "127.0.0.1",
  "port": 48731,
  "token": "uuid-token",
  "claim": "uuid-claim",
  "protocolVersion": 1,
  "expiresAt": "2026-06-23T00:10:00Z",
  "claimedAt": null
}
```

字段：
- `token`：会话级授权 token
- `claim`：一次性声明令牌（用于 `/pairing/claim`）
- `expiresAt`：token 过期时间
- `claimedAt`：null 表示尚未被 claim

### `GET /pairing/claim?claim=<uuid-claim>`

一次性 claim。调用成功后：
- `claimedAt` 设为首调用时间
- 后续同一 claim 再调用返回 `409 Conflict`
- 成功后返回完整 pairing payload（含 claimedAt）

返回 `401` 情况：
- claim 不匹配
- token 已过期

### `GET /snapshot?token=<token>`

返回当前 relay snapshot：

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

## Auth Flow

### HTTP Auth

每个需要授权的端点通过两种方式之一传入 token：

1. **Query parameter**：`?token=<token>`
2. **Authorization header**：`Authorization: Bearer <token>`

无 token 或 token 无效 → `401 Unauthorized`。

### WebSocket Auth

WebSocket 连接建立后，第一条消息必须是：

```json
{
  "type": "mac-relay.authorize",
  "payload": {
    "token": "<pairing-token>"
  }
}
```

- 成功 → 返回 `{"type": "mac-relay.authenticated", "payload": {"status": "ok"}}`，后续消息可调用正常命令
- 失败 → 返回 `{"type": "error", "payload": {"error": "..."}}` 并关闭连接
- 若第一条消息不是 `mac-relay.authorize`，返回错误并关闭

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

### Events (server → client)

| type | 说明 |
|------|------|
| `session.snapshot` | snapshot response |
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
  "payload": {
    "error": "描述信息"
  }
}
```

## Pairing Flow

1. **Mac 启动 relay**
   - 生成 pairing token 和 claim
   - `GET /pairing` 返回 payload（含 token、claim、expiresAt）
2. **二维码展示**
   - Mac 将 pairing payload JSON 编码进二维码
3. **iPhone 扫码**
   - 解析二维码获取 host、port、token、claim
4. **iPhone claim**
   - 调用 `GET /pairing/claim?claim=<claim>`
   - 成功后获取完整配对数据
5. **iPhone 连接 WebSocket**
   - 使用 token 完成 `mac-relay.authorize`
6. **正常通信**
   - snapshot / replay / heartbeat

## iPhone 客户端第一版接入步骤

1. 扫描 Mac 上显示的二维码
2. 解析 `RelayPairingPayload`（host、port、token、claim、protocolVersion）
3. 连接 WebSocket：`ws://<host>:<port>/relay`
4. 首条消息发送 `mac-relay.authorize` 携带 token
5. 收到 `mac-relay.authenticated` 后：
   - 调用 `snapshot.get` 获取当前完整状态
   - 开始监听事件或发送后续命令
6. 定期发送 `heartbeat.ping` 保持连接

## 当前限制与后续方向

- **配对数据已在 Keychain**：`KeychainPairingCredentialStore` 持久化 token/claim/deviceID，重启可恢复。Memory store 保留供测试使用。
- **device trust 已实现**：支持 device registration + challenge-response (SHA256 / HMAC-SHA256)。
- **局域网发现**：当前依赖扫码 + 直连 IP / `macrelay://` URI；后续可增加 Bonjour 发现。
- **WebSocket reconnect**：断线后心跳 loop 自动重连（指数退避），恢复 snapshot/replay。
- **approval flow**：已通过 `RelayRuntimeCommandDispatcher` 和 fake probe 验证，真实 `approval.resolve` 有 gated live probe（`MACRELAY_RUN_LIVE_APPROVAL=1`）。
