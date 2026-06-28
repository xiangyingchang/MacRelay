# MacRelay

**Mac ↔ iPhone 局域网配对通信桥梁** — 让 iPhone 远程操控 Mac 上 Codex CLI / Claude Code 的 AI 编程会话。

## 功能

- **双引擎支持**：Codex CLI 和 Claude Code 无缝切换
- **会话管理**：创建、查看历史、搜索筛选、保存到工作区
- **消息同步**：Mac 与 iPhone 双向实时同步
- **工作区日志**：每次对话自动记录到 `.macrelay/sessions/`
- **空间记忆**：`.macrelay/memory.md` 累积项目上下文
- **暗/亮主题**：Geist 设计系统，支持深色/浅色切换
- **侧边栏折叠**：可拖拽调整宽度（180–400px）
- **手机配对**：扫码连接，局域网实时通信

## 快速开始

```bash
# 环境要求
# - macOS 14+
# - Swift 5.10+
# - Codex CLI 或 Claude Code（至少一个）

# 编译 Mac 客户端
cd macrelay-project
swift build

# 打包 .app bundle
scripts/build-mac-shell-app.sh
open .build/AgentClientMacShell.app

# iOS 模拟器
scripts/build-ios.sh

# iOS 真机（需要 Xcode + 个人证书）
open Apps/MacRelayiOSApp/MacRelayiOSApp.xcodeproj
# → 选 MacRelayiOSApp scheme → iPhone → Personal Team → ⌘R
```

## 架构

```
iPhone App (SwiftUI) ──WebSocket──→ Mac .app ──JSON-RPC──→ Codex CLI / Claude Code
       │                              │
       └── macrelay://pair URI ─────→ MacRelayHTTPServer
```

| 模块 | 作用 |
|------|------|
| `AgentRuntime` | 统一基类，Codex CLI / Claude Code 共用 |
| `CodexRuntime` | Codex CLI app-server JSON-RPC |
| `ClaudeCodeRuntime` | Claude Code app-server JSON-RPC |
| `MacRelayService` | 事件归约 + 状态快照 + 广播 |
| `SessionJournal` | 对话日志 + 空间记忆持久化 |

## 技术栈

- **语言**：Swift 5.10
- **UI 框架**：SwiftUI（macOS 14+ / iOS 17+）
- **通信**：WebSocket + HTTP（Network.framework）
- **协议**：JSON-RPC 2.0 over stdio
- **设计系统**：Geist（Vercel），参考 `DESIGN.md`

## 设计

配色、间距、字体等设计规范详见 [`DESIGN.md`](./DESIGN.md)。  
HTML 交互原型见 [`design-prototype.html`](./design-prototype.html)。  
协议文档见 [`docs/MacRelay 协议文档.md`](./docs/MacRelay%20协议文档.md)。

## License

MIT
