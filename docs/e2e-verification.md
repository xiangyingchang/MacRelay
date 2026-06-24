# MacRelay 端到端手动验收指南

最后更新：2026-06-23  
对应 HEAD：`git rev-parse --short HEAD`

## 前置条件

- macOS 14+，Xcode 26+（含 iOS 17+ simulator）
- Codex CLI 已安装（`~/.npm-global/bin/codex`）
- 本仓库位于 `/private/tmp/MacRelay`
- **真机配对需要**：Mac 和 iPhone 连接同一 Wi‑Fi；Mac 防火墙允许 `AgentClientMacShell` 入站连接；Mac Inspector 中 Host mode 设为 "LAN"
- **真机部署**：必须通过 Xcode 打开 `Package.swift`，选择 MacRelayiOS scheme + iPhone destination + Personal Team 签名，直接 Run 即可。SwiftPM CLI 不支持真机 codesign。
  - 详细步骤见 `scripts/build-ios-device.sh`

## Step 1 — 启动 Mac Relay

```bash
cd /private/tmp/MacRelay
swift build

# 启动 Mac App shell（会启动 HTTP relay + WebSocket relay）
.build/debug/AgentClientMacShell
```

或直接启动 HTTP relay 探针验证：

```bash
.build/debug/MacRelayHTTPServerProbe
# → MacRelayHTTPServerProbe passed port=48731
```

## Step 2 — 获取 Pairing Payload

在 Mac Inspector 的 "Mac Relay" 区域：
- **Host mode** 选择器：Simulator/本机选 **Localhost**，真机选 **LAN**
- 如果 LAN 无法发现 IP，会自动 fallback 到 localhost 并显示警告

```
host: 127.0.0.1
port: 48731
token: xxxxxxxx-xxxx-xxxx...
claim: yyyyyyyy-yyyy-yyyy...
deviceID: zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz
expires: 580s
version: 1
```

也可以直接 curl：

```bash
curl http://127.0.0.1:48731/pairing
```

如需 rotate（更换 token/claim）：

```bash
# 在 Mac Inspector 点击 "Rotate" 按钮
# 或代码调用 relayHTTPServer.rotatePairingToken()
```

## Step 3 — 启动 iOS Simulator App

```bash
./scripts/build-ios.sh
```

这将：
1. 为 iOS Simulator 构建 `MacRelayiOS`
2. 生成 `.app` bundle
3. 安装到 booted simulator
4. 启动 App

## Step 4 — 完成 Pairing

在 iOS Simulator App 中：

1. **Pairing 标签页**
2. 将 Step 2 中 Mac Inspector 显示的 URI（`macrelay://pair?...`）或完整 JSON payload 粘贴到输入框中
3. 点击 **Claim** 按钮
4. App 会：
   - 调用 `GET /pairing/claim?claim=...` 完成一次性声明
   - 连接 WebSocket，发送 `mac-relay.authorize` 携带 token
   - 进入 "Connected" 状态

## Step 5 — 查看 Session

切换到 **Session 标签页**：
- 看到连接状态指示（绿色圆点 = connected）
- 可点击 **Refresh** 拉取最新 snapshot + replay events
- 看到 Codex session 的状态（如果有正在运行的 session）

## ⚠️ Codex 额度消耗说明

**以下操作会消耗 Codex 模型额度，默认不运行：**

| 命令 | 说明 |
|------|------|
| `MACRELAY_RUN_LIVE_CODEX=1 .build/debug/RelayCommandLiveProbe` | 验证 settings.update + tiny turn |
| `MACRELAY_RUN_LIVE_APPROVAL=1 .build/debug/RelayApprovalLiveProbe` | 验证 readOnly sandbox 触发 approval |
| `codex app-server --stdio` 手动交互 | 真实 Codex session |

**以下操作不消耗额度，可随时运行：**

```bash
swift build && swift test
.build/debug/MacRelayHTTPServerProbe
.build/debug/MacRelayWebSocketServerProbe
.build/debug/RelayRuntimeCommandDispatcherProbe
.build/debug/AgentClientIOProbe
.build/debug/RealStateMachineLoopProbe
.build/debug/ChallengeSignerProbe
.build/debug/iPhoneSimClientProbe
```

## 故障排除

| 症状 | 可能原因 | 解决方法 |
|------|---------|---------|
| iOS App 连接失败 | Mac relay 未启动 | 检查 Mac Inspector 的 "Mac Relay" section 是否为 "Running" |
| Claim 返回 401 | token 已过期 | 在 Mac Inspector 点击 "Rotate" 获取新 payload |
| Claim 返回 409 | claim 已被使用 | 同上，rotate 获取新 payload |
| WebSocket 连接超时 | 防火墙阻止 127.0.0.1 | 确认 Mac 防火墙允许 AgentClientMacShell |
| 看不到 session 数据 | Mac 没有活跃的 Codex session | 使用 `.build/debug/MacRelayServiceFixtureProbe` 创建 mock session |
