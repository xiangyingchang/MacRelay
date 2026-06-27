# MacRelay 项目长期记录

## 项目定位
local-first macOS ↔ iPhone AI编程CLI中继工具。
- Mac 是执行端（运行 Codex CLI / Claude Code），iPhone 是完整远程操控端
- 局域网直连，不做云端中继，不做账号体系，隐私优先

## 技术栈
- Swift / SwiftUI 原生双端，Swift Package Manager
- 通信：HTTP（配对/快照/回放）+ WebSocket（标准协议，Token 或挑战认证）
- 认证：Keychain 持久化设备凭证，SHA256/HMAC-SHA256 挑战响应
- 平台：macOS 14+，iOS 17+

## 模块分层
1. AgentClientCore — 共享模型、事件存储、中继协议、认证、状态机
2. AgentClientIO — iOS/Mac HTTP + WebSocket 客户端库
3. AgentClientiOS — SwiftUI 视图 + ViewModel（iPhone）
4. AgentClientMacShell — macOS SwiftUI + Inspector
5. MacRelayiOS — iOS @main 应用目标

## 当前进度（截至 2026-06-27）
- 已完成：配对、中继、状态同步主干
- 未完成：App Store 分发管道、approval.resolve live、加密 QR payload、iOS Keychain 扩展共享

## 文档结构
- docs/AI 编程 CLI 客户端需求文档.md — 完整 PRD（含架构、MVP、安全设计）
- docs/MacRelay 协议文档.md — HTTP/WS 接口、认证流程、错误码
- docs/e2e-verification.md — 手动端到端验证步骤
- docs/AI 编程 CLI 客户端 Mac Relay 技术设计.md — 技术设计细节
- docs/AI 编程 CLI 客户端 UI 设计基准.md — UI 规范
- docs/AI 编程 CLI 客户端落地执行计划.md — 执行计划

## Probe 说明
大量独立可执行探针用于验证各子功能，不消耗 Codex 配额。
Live Probe（需配额）用 MACRELAY_RUN_LIVE_CODEX=1 环境变量启用。
