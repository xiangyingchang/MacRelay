import SwiftUI

// Geist design system — Dark theme
// https://vercel.com/design.dark.md
enum Theme {
    // Backgrounds
    static let bgPrimary = Color(hex: "#151515")
    static let bgSecondary = Color(hex: "#252728")
    static let bgTertiary = Color(hex: "#303233")
    static let bgHover = Color(hex: "#3a3c3d")
    static let codeBg = Color(hex: "#111111")
    static let canvas = Color(hex: "#111111")
    static let elevated = Color(hex: "#2d2f30")

    // Bubbles / surfaces
    static let agentBubble = Color(hex: "#202122")
    static let userBubble = Color(hex: "#2f5f8f")

    // Accent
    static let accent = Color(hex: "#4c9cff")
    static let accentText = Color(hex: "#75b7ff")
    static let accentSubtle = Color(hex: "#18344e")

    // Semantic
    static let success = Color(hex: "#31c46b")
    static let warning = Color(hex: "#f6a83a")
    static let warningBg = Color(hex: "#4b3218")
    static let error = Color(hex: "#ff5b68")

    // Text
    static let textPrimary = Color(hex: "#f1f1f1")
    static let textSecondary = Color(hex: "#b8b8b8")
    static let textMuted = Color(hex: "#8d8d8d")

    // Borders
    static let border = Color(hex: "#383a3b")
    static let borderBright = Color(hex: "#525557")

    // Geist rounded tokens
    static let radiusSm: CGFloat = 6
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
