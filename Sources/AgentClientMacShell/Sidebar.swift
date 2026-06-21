import SwiftUI

struct Sidebar: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        VStack(spacing: 0) {
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
                    IconOnlyButton(systemName: "sidebar.left")
                }

                VStack(spacing: 4) {
                    ForEach(viewModel.navItems) { item in
                        NavRow(
                            item: item,
                            isActive: item.title == viewModel.activeNav,
                            action: { viewModel.activeNav = item.title }
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("RECENT SESSIONS")
                    ForEach(viewModel.sessions) { session in
                        SidebarSessionRow(
                            session: session,
                            isActive: session.id == viewModel.activeRunID,
                            action: { viewModel.activeRunID = session.id }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            Spacer()

            Group {
                if viewModel.runtimeMode == .real {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "desktopcomputer")
                            Text(viewModel.runtime.currentThreadID != nil ? "Session active" : "No session")
                                .lineLimit(1)
                            Spacer()
                            StatusPill(text: viewModel.realSessionStatusText, tone: viewModel.realSessionStatusTone)
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
                } else {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "desktopcomputer")
                            Text(viewModel.snapshot.connection.macName ?? "MacBook Pro")
                                .lineLimit(1)
                            Spacer()
                            StatusPill(text: "Online", tone: .success)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)

                        HStack(spacing: 8) {
                            Image(systemName: "iphone")
                            Text("iPhone paired")
                            Spacer()
                            Text("Seq \(viewModel.snapshot.lastEventSeq)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                    }
                }
            }
            .padding(10)
            .background(Theme.bgSecondary)
            .overlay(Rule(horizontal: true), alignment: .top)
        }
        .background(Theme.bgSecondary)
    }
}

struct NavRow: View {
    let item: NavItem
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(isActive ? Theme.accentText : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isActive ? Theme.accentSubtle : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct SidebarSessionRow: View {
    let session: SessionListItem
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                StatusDot(status: session.status)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isActive ? Theme.accentText : Theme.textSecondary)
                        .lineLimit(1)
                    Text(session.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                if session.count > 0 {
                    Text("\(session.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Theme.accent)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isActive ? Theme.accentSubtle : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct ActiveSessionsBar: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.runs) { run in
                ActiveRunChip(
                    run: run,
                    isActive: run.id == viewModel.activeRunID,
                    action: { viewModel.activeRunID = run.id }
                )
            }
            Button(action: {}) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .background(Theme.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer()
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .background(Theme.bgPrimary)
    }
}

struct ActiveRunChip: View {
    let run: ActiveRun
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(run.status == "running" ? Theme.accentText : Theme.textMuted)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: run.status == "running" ? "bolt.fill" : "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.bgSecondary)
                    )
                Text(run.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(isActive ? Theme.bgTertiary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}
