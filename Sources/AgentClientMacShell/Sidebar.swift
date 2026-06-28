import SwiftUI

struct Sidebar: View {
    @ObservedObject var viewModel: MacShellViewModel
    let toggleSidebar: () -> Void
    @Binding var showPhonePopover: Bool
    @Binding var showSettingsPopover: Bool
    @State private var sessionsExpanded = true
    @State private var workspaceExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // Toggle button
            HStack {
                Spacer()
                IconOnlyButton(systemName: "sidebar.left", action: toggleSidebar)
            }
            .padding(.trailing, 6)
            .padding(.top, 5)
            .ignoresSafeArea(edges: .top)

            // New task button
            NewTaskButton(action: viewModel.startNewSession)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            // Session list — active sessions only (not saved to workspace)
            CollapsibleSectionHeader(
                title: "会话",
                count: viewModel.activeSessions.count,
                isExpanded: $sessionsExpanded
            )
            // Scrollable content area
            ScrollView {
                VStack(spacing: 0) {
                    if sessionsExpanded, !viewModel.activeSessions.isEmpty {
                        SessionListView(
                            sessions: viewModel.activeSessions,
                            activeID: viewModel.activeRunID,
                            select: { id in
                                viewModel.activeNav = "Sessions"
                                viewModel.selectSession(id: id)
                            },
                            onDelete: { id in viewModel.deleteSession(id: id) },
                            onSave: { id in viewModel.saveSessionToWorkspace(id: id) }
                        )
                    }

                    // Workspace section — shows saved sessions
                    CollapsibleSectionHeader(
                        title: "空间",
                        count: viewModel.workspaceSessions.count,
                        isExpanded: $workspaceExpanded
                    )
                    .padding(.top, 4)
                    if workspaceExpanded {
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.muted)
                                Text(viewModel.workspaceFolderName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.fg)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)

                            if !viewModel.workspaceSessions.isEmpty {
                                ForEach(viewModel.workspaceSessions) { session in
                                    SessionRow(
                                        item: session,
                                        isActive: session.id == viewModel.activeRunID,
                                        action: {
                                            viewModel.activeNav = "Sessions"
                                            viewModel.selectSession(id: session.id)
                                        },
                                        onDelete: { viewModel.deleteSession(id: session.id) },
                                        onSave: nil
                                    )
                                    .padding(.leading, 20)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            // Bottom footer (fixed)
            SidebarFooter(viewModel: viewModel, showPhonePopover: $showPhonePopover, showSettingsPopover: $showSettingsPopover)
        }
        .background(Theme.sidebarBg)
    }
}

// MARK: - New Task Button
struct NewTaskButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                Text("新建任务")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSm)
                .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        .contentShape(Rectangle())
    }
}

// MARK: - Collapsible Section Header

struct CollapsibleSectionHeader: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        Button(action: { isExpanded.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeOut(duration: 0.12), value: isExpanded)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .tracking(0.6)
                    .textCase(.uppercase)
                Text("(\(count))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted.opacity(0.6))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

// MARK: - Session List
struct SessionListView: View {
    let sessions: [SessionListItem]
    let activeID: String
    let select: (String) -> Void
    let onDelete: ((String) -> Void)?
    let onSave: ((String) -> Void)?

    init(sessions: [SessionListItem], activeID: String, select: @escaping (String) -> Void, onDelete: ((String) -> Void)? = nil, onSave: ((String) -> Void)? = nil) {
        self.sessions = sessions
        self.activeID = activeID
        self.select = select
        self.onDelete = onDelete
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(sessions) { item in
                SessionRow(
                    item: item,
                    isActive: item.id == activeID,
                    action: { select(item.id) },
                    onDelete: onDelete.map { cb in { cb(item.id) } },
                    onSave: onSave.map { cb in { cb(item.id) } }
                )
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Session Row
struct SessionRow: View {
    let item: SessionListItem
    let isActive: Bool
    let action: () -> Void
    var onDelete: (() -> Void)?
    var onSave: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(isActive ? Theme.accent : Theme.muted.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                }
                .foregroundStyle(isActive ? Theme.fg : Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Menu {
                if let onSave {
                    Button(action: onSave) {
                        Label("保存到空间", systemImage: "tray.and.arrow.down")
                    }
                }
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("删除", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .opacity(isHovering ? 1 : 0)
            .scaleEffect(isHovering ? 1 : 0.8, anchor: .trailing)
        }
        .animation(.smooth(duration: 0.12), value: isHovering)
        .onHover { hovering in isHovering = hovering }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .background(isActive ? Theme.accent.opacity(0.12) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSm)
                .stroke(isActive ? Theme.accent.opacity(0.28) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
    }
}

// MARK: - Collapsed Sidebar
struct CollapsedSidebar: View {
    let toggleSidebar: () -> Void

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                Color.clear.frame(width: 62)
                IconOnlyButton(systemName: "sidebar.right", action: toggleSidebar)
                Spacer()
            }
            .padding(.top, 5)
            Spacer()
        }
        .frame(width: 100)
        .ignoresSafeArea(edges: .top)
        .background(Color.clear)
    }
}

// MARK: - Sidebar Footer
struct SidebarFooter: View {
    @ObservedObject var viewModel: MacShellViewModel
    @Binding var showPhonePopover: Bool
    @Binding var showSettingsPopover: Bool

    var body: some View {
        HStack(spacing: 4) {
            Button(action: { showSettingsPopover.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                    Text("设置")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .layoutPriority(1)

            Button(action: { showPhonePopover.toggle() }) {
                Image(systemName: "iphone")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 34)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .overlay(Rule(horizontal: true), alignment: .top)
    }
}

// MARK: - Phone Pairing Popover
struct PhonePairingPopover: View {
    @ObservedObject var viewModel: MacShellViewModel
    @Binding var isPresented: Bool
    @State private var copied = false

    var body: some View {
        let running = viewModel.relayServerRunning

        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("手机配对")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.fg)
                    if running {
                        Text("已连接")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.success)
                    }
                }
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .background(Theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .bottom)

            if running {
                // QR code + status (side by side)
                HStack(spacing: 14) {
                    // QR code
                    if let qrImage = viewModel.relayPairingQRImage {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 72, height: 72)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 72, height: 72)
                            .overlay(
                                Image(systemName: "qrcode")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Theme.muted)
                            )
                    }

                    // Quick status
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.success).frame(width: 6, height: 6)
                            Text("已连接")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.success)
                        }
                        DetailLine(key: "主机", value: viewModel.relayServerHost)
                        DetailLine(key: "端口", value: "\(viewModel.relayServerPort)")
                    }
                    Spacer()
                }
                .padding(16)

                Rectangle().fill(Theme.border).frame(height: 1)
                    .padding(.horizontal, 0)

                // URI
                VStack(alignment: .leading, spacing: 4) {
                    Text("配对 URI")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(viewModel.relayPairingURI)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(viewModel.relayPairingURI, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    }) {
                        Text(copied ? "已复制" : "复制 URI")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)

                    Button(action: viewModel.rotateRelayPairing) {
                        Text("刷新二维码")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.fg)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            } else {
                // Empty state
                VStack(spacing: 10) {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.muted)
                    Text("中继未启动")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 290)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMd)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
    }
}

struct DetailLine: View {
    let key: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(key.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .tracking(0.4)
                .frame(width: 32, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.fg)
        }
    }
}

// MARK: - Settings Panel (left-side replacement for sidebar)
struct SettingsPopover: View {
    @ObservedObject var viewModel: MacShellViewModel
    let isLightTheme: Bool
    let toggleTheme: () -> Void
    @Binding var isPresented: Bool

    @AppStorage("agentProvider") private var agentProvider: String = "Codex CLI"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — close button only
            HStack {
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Title
            Text("设置")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.fg)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)

            // Provider
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 18)
                    Text("模型提供方")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.fg)
                    Spacer()
                }
                HStack(spacing: 0) {
                    ForEach(["Codex CLI", "Claude Code"], id: \.self) { provider in
                        Button(action: {
                            if agentProvider != provider {
                                agentProvider = provider
                                viewModel.switchProvider(to: provider)
                            }
                        }) {
                            Text(provider)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(agentProvider == provider ? Theme.accentFg : Theme.muted)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .background(agentProvider == provider ? Theme.accent : Color.clear)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // Appearance
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 18)
                    Text("外观")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.fg)
                    Spacer()
                }
                HStack(spacing: 0) {
                    Button(action: { if isLightTheme { toggleTheme() } }) {
                        Text("深色")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isLightTheme ? Theme.muted : Theme.accentFg)
                            .padding(.horizontal, 14)
                            .frame(height: 28)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .background(isLightTheme ? Color.clear : Theme.accent)

                    Button(action: { if !isLightTheme { toggleTheme() } }) {
                        Text("浅色")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isLightTheme ? Theme.accentFg : Theme.muted)
                            .padding(.horizontal, 14)
                            .frame(height: 28)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .background(isLightTheme ? Theme.accent : Color.clear)
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: 240)
        .background(Theme.sidebarBg)
        .overlay(Rectangle().fill(Theme.border).frame(width: 1), alignment: .trailing)
    }
}

