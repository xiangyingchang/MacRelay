# MacRelay 设计规范 (Design System)

> 基于 `design-prototype.html` 提取。所有值以本文档为准。
> HTML 原型作为视觉参考，SwiftUI 实现直接引用本文档的 token 值。

---

## 1. 颜色系统 (Color Tokens)

### 1.1 核心调色板

| Token | 深色模式 (Dark) | 浅色模式 (Light) | SwiftUI 命名 | 用途 |
|---|---|---|---|---|
| `--bg` | `#191816` | `#f6f5f1` | `Color.bg` | 页面背景（主区域） |
| `--surface` | `#23211e` | `#ffffff` | `Color.surface` | 卡片、弹窗、输入框 |
| `--fg` | `#edebe5` | `#1e1d1a` | `Color.fg` | 主要文字 |
| `--muted` | `#8f8b80` | `#88847a` | `Color.muted` | 次要文字、占位符 |
| `--border` | `#33312b` | `#e4e2da` | `Color.border` | 边框、分割线 |
| `--accent` | `#56b0a4` | `#3a8b80` | `Color.accent` | 强调色（操作、活跃状态） |
| `--accent-fg` | `#0d0c0a` | `#ffffff` | `Color.accentFg` | 强调色上的文字（按钮文字） |

### 1.2 语义色

| 含义 | 色值 | 用途 |
|---|---|---|
| 成功 | `#4caf50` | 连接成功、绿色圆点 |
| 警告 | `#f6a83a` | 待审批、黄色状态 |
| 错误 | `#e57373` | 丢弃、删除操作 |

### 1.3 派生色（不单独定义，由 Color 扩展计算）

| Token | 公式 | 用途 |
|---|---|---|
| `--accent-soft` | `accent` 以 14-15% 透明度叠加 | 强调色背景、选中行底色 |
| `--sidebar-active` | `accent` 以 10-12% 透明度叠加于 `sidebar-bg` | 侧栏选中项 |

### 1.4 文字颜色

| 用途 | 颜色 token |
|---|---|
| 主标题（标题栏、消息标题） | `--fg` |
| 次要文字（元信息、描述） | `--muted` |
| 你的消息角色标签 | `--accent`（`.user-role`） |
| 代码块文字 | 同 `--fg`，背景用 `--bg` |
| 禁用状态文字 | `--muted opacity 0.5` |

---

## 2. 字体系统 (Typography)

### 2.1 字体栈

| 角色 | 字体 | CSS token | SwiftUI |
|---|---|---|---|
| Display | SF Pro Display, system-ui, sans-serif | `--font-display` | `.system(.large, design: .default)` |
| Body | SF Pro Text, system-ui, sans-serif | `--font-body` | `.system(.body)` / `.system(.subheadline)` |
| Mono | SF Mono, Menlo, monospace | `--font-mono` | `.system(.caption, design: .monospaced)` / `.monospaced()` |

### 2.2 字号系统

| 上下文 | 大小 | 字重 | 对应 SwiftUI |
|---|---|---|---|
| 对话标题（标题栏） | 15px | 600 (Semibold) | `.headline` 或 `.system(size: 15, weight: .semibold)` |
| 状态标签 | 10px | 600 | `.caption2.weight(.semibold)` |
| 会话名称 | 13px | 600 | `.subheadline.weight(.semibold)` |
| 会话元信息 | 11px | 400 | `.caption` |
| 消息正文 | 14px | 400 | `.callout` 或 `.system(size: 14)` |
| 消息角色标签 | 11px | 600 | `.caption.weight(.semibold)` |
| 代码内联 | 12px | 400 monospace | `.system(size: 12, design: .monospaced)` |
| 侧栏标签（会话、设置） | 11px | 700 | `.caption.weight(.bold)` |
| 输入框文字 | 14px | 400 | `.system(size: 14)` |
| 空状态提示 | 15px | 400 | `.system(size: 15)` |
| 弹出面板标题 | 13px / 15px | 600 | `.subheadline.weight(.semibold)` |
| 按钮/芯片文字 | 11-12px | 500 | `.caption.weight(.medium)` |

### 2.3 行高

- 正文：`1.55` ~ `1.65`
- 消息：`lineSpacing(3)`

---

## 3. 间距系统 (Spacing)

基于 4px 栅格，常用间距：

| 名称 | 值 | 典型用途 |
|---|---|---|
| `spacing.xxs` | 4px | 极小间距 |
| `spacing.xs` | 6-8px | 图标与文字间距、圆角按钮内边距 |
| `spacing.sm` | 10-12px | 列表项内边距、组件内间距 |
| `spacing.md` | 14-16px | 卡片内边距、消息间距 |
| `spacing.lg` | 20-24px | 区域间距、输入框边距 |
| `spacing.xl` | 32px | 大区块间距 |

---

## 4. 圆角系统 (Border Radius)

| Token | 值 | 用途 |
|---|---|---|
| `--radius-sm` | `8px` | 按钮、输入框、列表项、小卡片 |
| `--radius-md` | `12px` | 消息卡片、弹窗、输入框容器 |
| `--radius-lg` | `16px` | 大卡片、弹窗、设置面板 |
| `--radius-xl` | `20px` | 窗口圆角 |

---

## 5. 阴影 (Shadows)

| 层级 | 深色模式 | 浅色模式 | 用途 |
|---|---|---|---|
| 低（card） | `0 1px 3px rgba(0,0,0,0.2)` | `0 1px 3px rgba(0,0,0,0.04)` + `0 1px 2px rgba(0,0,0,0.03)` | 输入框、小卡片 |
| 高（popover） | `0 8px 24px rgba(0,0,0,0.3)` | `0 4px 16px rgba(0,0,0,0.06)` + `0 2px 6px rgba(0,0,0,0.04)` | 弹窗、下拉面板 |
| 窗口 | `0 16px 48px rgba(0,0,0,0.2)` + `0 2px 8px rgba(0,0,0,0.06)` | 同左 | 应用窗口 |

---

## 6. 布局系统 (Layout)

### 6.1 三栏结构

| 栏 | 宽度 | 背景色 | SwiftUI View |
|---|---|---|---|
| 第 1 栏 - 侧栏 | 240px | `--sidebar-bg` | `Sidebar` |
| 第 2 栏 - 对话 | flex: 1 | `--bg` | `ChatWorkspace` |
| 第 3 栏 - 面板 | 290px | `--sidebar-bg` | `Inspector` |

栏间距：`1px`，使用 `--border` 颜色。

### 6.2 标题栏三段

| 段 | 宽度 | 背景色 | 内容 |
|---|---|---|---|
| s1 | 240px | `--sidebar-bg` | 交通灯 |
| s2 | flex: 1 | `--bg` | 对话标题 + 状态标签 |
| s3 | 290px | `--sidebar-bg` | 右侧收起按钮 |

### 6.3 窗口规格

- 最小尺寸：960 x 600
- 推荐尺寸：1320 x 820
- 标题栏高度：~40px

### 6.4 侧栏滚动区域

侧栏 (sidebar) 采用 flex 布局，内容区域可滚动：
- 顶部：新建任务模块（固定高度）
- 中间：会话列表（`flex: 1; overflow-y: auto`）
- 底部：设置 + 手机按钮（固定高度）

---

## 7. 组件规范 (Components)

### 7.1 侧栏会话项 (SessionItem)

| 状态 | 背景 | 左侧指示 | 文字颜色 |
|---|---|---|---|
| 默认 | 透明 | 无 | `--muted` |
| hover | `--sidebar-hover` | 无 | `--fg` |
| active | `--sidebar-active` | 3px 竖线 `--accent` | `--fg` |

结构：`[6px dot] [名称 + 元信息] [✓ 标记]`

### 7.2 新建任务按钮 (NewTaskBtn)

- 虚线边框 `1px dashed var(--border)` → hover 时变为实线 `--accent`
- 图标：圆圈 + 加号 (18x18)
- hover 背景：`--sidebar-active`
- 圆角：`--radius-sm` (8px)

### 7.3 消息卡片 (Message)

| 角色 | 头像背景 | 头像图标 | 卡片背景 | 角色标签色 |
|---|---|---|---|---|
| 你 (User) | `--accent-soft` | 无/自定义 | `--surface` | `--accent` |
| Codex (Assistant) | `--surface` | 自定义 | `--surface` | `--muted` |

- 卡片尺寸：`border: 1px solid var(--border); border-radius: var(--radius-md); padding: 12px 16px`
- 消息间距：16px（`padding: 16px 0`）
- 消息间分割：`border-top: 1px solid var(--border)`

### 7.4 输入框 (Composer)

| 状态 | 边框 | 背景 | 阴影 |
|---|---|---|---|
| 默认 | `--border` | `--surface` | `--card-shadow` |
| focus | `--accent` | `--surface` | + `0 0 0 3px var(--accent-soft)` |

- 圆角：`--radius-md` (12px)
- 可拖拽调整高度（48px ~ 320px），顶部 8px 区域光标变 `ns-resize`
- placeholder 颜色：`--muted` opacity 0.7

### 7.5 输入框工具栏芯片 (ComposerChip)

| 状态 | 边框 | 背景 | 文字色 |
|---|---|---|---|
| 默认 | `--border` | `--bg` | `--muted` |
| hover/active | `--accent` | `--accent-soft` | `--accent` |

### 7.6 输入框发送按钮 (ComposerSend)

- 背景：`--accent`
- 文字：`--accent-fg`
- 圆角：`--radius-sm` (8px)
- 禁用：opacity 0.3

### 7.7 工作区选择器 (WorkspacePicker)

- 透明无边框，hover 后出现 `--sidebar-hover` 背景
- 文件夹图标 + 路径文字
- 文字溢出时截断显示 `…`

### 7.8 右侧面板折叠区 (InspectorSection)

| 元素 | 样式 |
|---|---|
| 标题行 | `padding: 8px 10px`，hover 变 `--sidebar-hover` |
| 展开/收起 | 小三角形旋转 90° |
| 内容区 | `padding: 8px 10px 10px`，上方 `border-top` |

### 7.9 文件行 (FileRow)

- 类型图标（首字母）：24x24，`--bg` 背景
- 文件路径：`--font-mono`, 11px, 溢出截断
- 操作按钮：批准（✓ 绿色）/ 丢弃（× 红色）

### 7.10 状态指示 (StatusDot + StatusRow)

| 颜色 | 含义 |
|---|---|
| 绿 `#4caf50` | 已连接、运行中、成功 |
| 蓝 `--accent` | Relay 活跃、信息 |
| 黄 `#f6a83a` | 待审批、警告 |

### 7.11 收起按钮 (SidebarToggle / InspectorToggle)

| 状态 | 左侧按钮 (sidebar) | 右侧按钮 (inspector) |
|---|---|---|
| 展开 | `left: 198px` | `right: 268px` |
| 收起 | `left: 14px` | `right: 8px` |
| 样式 | 透明无边框，20x20，hover 变 `--muted` |
| 图标 | 竖线 + 箭头，180° 旋转切换 |

### 7.12 手机配对弹窗 (PhonePopover)

- 位置：左下角，`bottom: 74px; left: 24px`
- 宽度：290px
- 圆角：`--radius-lg` (16px)
- 背景：`--surface`
- 动画：`opacity 0.18s + transform translateY(8px)`

### 7.13 设置面板 (SettingsPopover)

- 从左侧滑出：`position: absolute; width: 240px; top: 0; left: 0`
- 动画：`opacity 0.18s + translateX(-20px)`
- 外观切换：双按钮分段控件（浅色/深色）

### 7.14 空状态 (EmptyState)

- 新建任务时显示，居中
- 只有文字「说说你在想什么」，无图标无按钮
- 输入框同步居中 (`main-area.centered`)

---

## 8. 交互规范 (Interaction)

### 8.1 动画时长

| 场景 | 时长 | 缓动 |
|---|---|---|
| hover 状态 | 0.1s | ease |
| 按钮点击 | 0.12s | ease |
| 弹窗出现/消失 | 0.18s | ease |
| 侧栏折叠/展开 | 0.2s | ease |
| 消息加载 | 0.18s | easeOut |

### 8.2 侧栏折叠

- 点击收起按钮：侧栏 (240px) 宽度变为 0，标题栏 s1 同步收起
- 收起后按钮出现在对话区左上角
- 点击展开按钮：恢复 240px
- 右侧面板折叠同理（290px）

### 8.3 输入框拖拽

- 顶部 8px 区域 `cursor: ns-resize`
- 向上拖 → 增高（上限 320px）
- 向下拖 → 变矮（下限 48px）
- 配合 `user-select: none` 防文本选中

### 8.4 主题切换

- 设置在设置面板内
- 两个状态按钮（浅色/深色），active 用 `--accent` 填充
- 所有颜色 token 在 light/dark 两套间切换

### 8.5 新建任务交互

- 点击「新建任务」→ 对话区居中，显示「说说你在想什么」
- 点击任一已有会话 → 对话区恢复正常布局（输入框在底部），显示该会话消息

---

## 9. 图层与 z-index

| 层级 | z-index | 元素 |
|---|---|---|
| 基础内容 | auto | 侧栏、对话、面板 |
| 弹出覆盖 | 100 | 弹窗遮罩 |
| 弹窗面板 | 101 | 手机配对弹窗、设置面板 |
| 收起按钮 | 10 | 侧栏/面板收起按钮 |

---

## 10. SwiftUI 实现建议

### 10.1 Color 扩展

```swift
extension Color {
    static let bg = Color(hex: "#191816") // 需在 init 中判断暗/亮模式
    static let surface = Color(hex: "#23211e")
    static let fg = Color(hex: "#edebe5")
    static let muted = Color(hex: "#8f8b80")
    static let border = Color(hex: "#33312b")
    static let accent = Color(hex: "#56b0a4")
    static let accentFg = Color(hex: "#0d0c0a")
    static let sidebarBg = Color(hex: "#141311")
    static let sidebarHover = Color(hex: "#23211e")
}
```

### 10.2 暗/亮模式适配

使用 SwiftUI `@Environment(\.colorScheme)` 或自定义 `@AppStorage` 偏好存储：

```swift
struct MacRelayTheme: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(colorScheme == .dark ? Color.bg : Color.bgLight)
            .foregroundColor(colorScheme == .dark ? Color.fg : Color.fgLight)
    }
}
```

建议直接使用系统的暗/亮模式自动切换，或通过 `preferredColorScheme` 强制指定。
