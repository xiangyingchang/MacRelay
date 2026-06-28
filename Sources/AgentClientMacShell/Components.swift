import SwiftUI

// MARK: - Header Metric
struct HeaderMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.fg)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSm)
                .stroke(Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
    }
}

// MARK: - KeyValue
struct KeyValue: View {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .foregroundStyle(Theme.muted)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.fg)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 12))
    }
}

// MARK: - Role Badge
struct RoleBadge: View {
    let role: String

    var body: some View {
        ZStack {
            Circle()
                .fill(role == "Tool" ? Theme.warning.opacity(0.15) : Theme.accentSoft)
            Image(systemName: role == "Tool" ? "terminal" : role == "Approval" ? "lock.open" : "command")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(role == "Tool" ? Theme.warning : Theme.accent)
        }
        .frame(width: 30, height: 30)
    }
}

// MARK: - App Mark
struct AppMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent)
            Image(systemName: "command")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 34, height: 34)
    }
}

// MARK: - Icon Button
struct IconOnlyButton: View {
    let systemName: String
    let action: () -> Void

    init(systemName: String, action: @escaping () -> Void = {}) {
        self.systemName = systemName
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSm)
                .stroke(Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
    }
}

// MARK: - Status Pill
struct StatusPill: View {
    enum Tone {
        case accent, success, warning, info, passive
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    var color: Color {
        switch tone {
        case .accent:  Theme.accent
        case .success: Theme.success
        case .warning: Theme.warning
        case .info:    Theme.muted
        case .passive: Theme.muted.opacity(0.6)
        }
    }
}

// MARK: - Status Dot
struct StatusDot: View {
    let status: String

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: status == "completed" ? 1 : 0)
            .background(Circle().fill(status == "completed" ? Color.clear : color))
            .frame(width: 8, height: 8)
    }

    var color: Color {
        switch status {
        case "running":   Theme.accent
        case "waiting":   Theme.warning
        case "completed": Theme.muted
        default:          Theme.muted
        }
    }
}

// MARK: - Divider
struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1, height: 20)
    }
}

struct Rule: View {
    var horizontal = false

    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: horizontal ? nil : 1, height: horizontal ? 1 : nil)
    }
}

// MARK: - Section Label
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.muted)
            .tracking(0.4)
    }
}
