# MacRelay 端到端手动验证指南

最后更新：2026-06-27

## 前置条件

- macOS 14+，Xcode 26+（含 iOS 17+ simulator）
- Codex CLI 已安装（`~/.npm-global/bin/codex`）
- 本仓库位于 `/private/tmp/MacRelay`
- **真机配对需要**：Mac 和 iPhone 连接同一 Wi‑Fi；Mac 防火墙允许 `AgentClientMacShell` 入站连接；Mac Inspector 中 Host mode 设为 "LAN"
- **真机部署**：必须通过 Xcode 打开 `Apps/MacRelayiOSApp/MacRelayiOSApp.xcodeproj`，选择 MacRelayiOSApp scheme + iPhone destination + Personal Team 签名。SwiftPM CLI 不支持真机 codesign。
  - 详细步骤见 `scripts/build-ios-device.sh`

## macOS Shell 验证

### 启动方式

```bash
# 开发模式（裸 executable，输入法可能不稳定）
swift build && open .build/debug/AgentClientMacShell

# 正式模式（.app bundle，推荐）
scripts/build-mac-shell-app.sh && open .build/AgentClientMacShell.app
```

### Inspector 布局

右侧 Inspector 从上到下依次：
1. **Changed Files** — 文件变更列表
2. **Diff Preview** — 差异预览
3. **Session** — session 元信息
4. **Codex Runtime** — Codex CLI 检测/启动
5. **Mac Relay**（含 Pairing 内嵌块）：
   - **PAIRING** 子区域：QR 码 + `macrelay://pair?...` URI（可复制）+ Host mode 选择器 + Rotate 按钮
   - Relay 状态：Running/Stopped + 端口 + Start/Stop/Snapshot 按钮
6. **Mock Commands** — 命令日志

### 输入框

Mac shell 底部输入框使用 `TextField(axis: .vertical)`（macOS 14+ 原生多行），已验证中文输入法候选窗正常。如果无法输入，检查是否以 `.app` bundle 方式运行。

## Step 1 — 环境检查

```bash
cd /private/tmp/MacRelay
scripts/check.sh
```

预期输出：
```
✅ All probes passed
⏭ Live probes skipped (env gate)
```

## Step 2 — 获取 Pairing Payload

在 Mac Inspector 的 "Mac Relay" 区域：
- **Host mode** 选择器：Simulator/本机选 **Localhost**，真机选 **LAN**
- 如果 LAN 无法发现 IP，会自动 fallback 到 localhost 并显示警告
- 点击 Start 启动 relay
- Pairing 区域会出现 QR 码 + `macrelay://pair?...` URI

## Step 3 — 配对验证（Simulator）

### 3a — 自动配对（扫码/URL scheme）

```bash
# 从 Mac Inspector 复制 pairing URI，然后：
xcrun simctl openurl booted "macrelay://pair?host=127.0.0.1&port=...&claim=..."
```

### 3b — 手动配对

1. 在 Simulator 中打开 MacRelay app
2. 在 Pairing tab 粘贴 URI
3. 点击 Claim & Connect
4. 验证：
   - 按钮显示 "Connecting..." → "Claim & Connect"
   - 状态指示变为 "Connected"
   - 切换到 Session tab 能看到 snapshot
   - 切换到 Log tab 能看到 replay events

### 3c — 断线重连

1. 在 Mac shell 中停止 relay（Mac Relay 区点 Stop）
2. Simulator 中观察状态变为 "Reconnecting..."
3. 在 Mac shell 中启动 relay（点 Start + Rotate）
4. Simulator 自动重连成功

### 3d — 清除配对

1. 在 Simulator app 中点击 Clear Pairing
2. 验证回到 Pairing 页面
3. 旧的 credential 不能再使用

## Step 4 — 真机配对验证

### 4a — Xcode 部署

```bash
open Apps/MacRelayiOSApp/MacRelayiOSApp.xcodeproj
# Xcode 中：
#   1. 选 MacRelayiOSApp scheme
#   2. 选 iPhone 真机
#   3. Signing → Personal Team
#   4. ⌘R
```

### 4b — Mac Shell 配置

```bash
open .build/AgentClientMacShell.app
# Mac Relay → Start
# Host mode → LAN（切换后 relay 重启，监听 LAN IP）
```

### 4c — iPhone 配对

1. iPhone 相机扫描 Mac Inspector 中的 QR 码
2. 自动打开 MacRelay app，触发 `onOpenURL`
3. 或 iPhone 中粘贴 URI → Claim & Connect

## 验证标准

- [ ] 全流程不崩溃
- [ ] HTTP 配对 + 409 防重放
- [ ] WebSocket auth（token 方式）
- [ ] snapshot / replay / heartbeat
- [ ] 断线自动重连
- [ ] 清除配对后不能复用旧 credential
- [ ] Host mode Localhost/LAN 切换正确
- [ ] 真机 HTTP 不因 ATS 被拦截
- [ ] live Codex probes 不自动运行

## 常见问题

| 问题 | 原因 | 解决 |
|------|------|------|
| 输入框无法输入 | 非 `.app` bundle 启动 | `scripts/build-mac-shell-app.sh && open .build/AgentClientMacShell.app` |
| 真机黑屏 | Keychain 主线程阻塞 / 缺 LaunchScreen | Clean Build Folder + re-run |
| Claim 无反应 | ATS 拦截 HTTP / 状态机卡住 | 更新代码到最新 + 重启 |
| WS 连接失败 | Mac 无 WS server / wsPort 不对 | 确认 Mac shell 已 Start relay |
| 扫码 URL scheme 不触发 | Info.plist 缺少 CFBundleURLTypes | 检查 MacRelayiOSApp 项目配置 |
