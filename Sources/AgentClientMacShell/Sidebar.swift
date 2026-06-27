import SwiftUI

struct Sidebar: View {
    @ObservedObject var viewModel: MacShellViewModel
    let toggleSidebar: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    AppMark()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CODEX ONE")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Local agent workspace")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    IconOnlyButton(systemName: "sidebar.left", action: toggleSidebar)
                }

                // Navigation items
                VStack(spacing: 4) {
                    ForEach(viewModel.navItems) { item in
                        NavRow(
                            item: item,
                            isActive: item.title == viewModel.activeNav,
                            action: {
                                viewModel.activeNav = item.title
                                if item.title == "Codex" {
                                    viewModel.startNewSession()
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)

            // Session list
            if !viewModel.displaySessions.isEmpty {
                SessionListView(
                    sessions: viewModel.displaySessions,
                    activeID: viewModel.activeRunID,
                    select: { id in
                        viewModel.activeRunID = id
                        viewModel.activeNav = "Sessions"
                        viewModel.selectSession(id: id)
                    }
                )
            }

            Spacer()

            // Status footer
            Group {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "desktopcomputer")
                        Text(viewModel.runtime.currentThreadID != nil ? "Session active" : "No session")
                            .lineLimit(1)
                        Spacer()
                        StatusPill(text: viewModel.sessionStatusText, tone: viewModel.sessionStatusTone)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                    HStack(spacing: 8) {
                        Image(systemName: viewModel.runtime.isAppServerRunning ? "bolt.fill" : "poweroff")
                        Text(viewModel.runtime.statusText)
                            .lineLimit(1)
                        Spacer()
                        if viewModel.runtime.snapshot.lastError != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.warning)
                            Text("Err")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.warning)
                        } else if viewModel.runtime.snapshot.status == .completed {
                            Text("Done")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.success)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                }
            }
            .padding(10)
            .background(Theme.elevated)
            .overlay(Rule(horizontal: true), alignment: .top)
        }
        .background(Theme.bgSecondary)
    }
}

// MARK: - Session List

struct SessionListView: View {
    let sessions: [SessionListItem]
    let activeID: String
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sessions")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Text("\(sessions.count) active")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(sessions) { item in
                        SessionRow(
                            item: item,
                            isActive: item.id == activeID,
                            action: { select(item.id) }
                        )
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }
}

struct SessionRow: View {
    let item: SessionListItem
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isActive ? Theme.accent : Theme.textMuted.opacity(0.3))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !item.status.isEmpty {
                    StatusPill(text: item.status, tone: item.status == "active" ? .info : .passive)
                }
            }
            .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isActive ? Theme.accentSubtle : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Theme.accent.opacity(0.28) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Nav Row

struct NavRow: View {
    let item: NavItem
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                    if item.title == "Codex" {
                        Text("New session")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isActive ? Theme.accentText.opacity(0.72) : Theme.textMuted)
                    }
                }
                Spacer()
            }
            .foregroundStyle(isActive ? Theme.accentText : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isActive ? Theme.accentSubtle : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? Theme.accent.opacity(0.28) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Collapsed Sidebar

struct CollapsedSidebar: View {
    let toggleSidebar: () -> Void

    var body: some View {
        VStack {
            IconOnlyButton(systemName: "sidebar.right", action: toggleSidebar)
                .padding(.top, 16)
            Spacer()
        }
        .frame(width: 44)
        .background(Theme.bgSecondary)
    }
}
