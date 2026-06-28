import SwiftUI

// MARK: - MacRelay Design System
// Reference: DESIGN.md — warm-neutral palette, teal accent

enum Theme {
    /// Reads current mode from UserDefaults so colors update reactively
    /// when the parent view's `.id()` changes.
    private static var isLight: Bool {
        UserDefaults.standard.string(forKey: "themeMode") == "light"
    }

    // ─── Backgrounds ─────────────────────────────────────────────
    static var bg: Color { isLight ? Light.bg : Dark.bg }
    static var surface: Color { isLight ? Light.surface : Dark.surface }
    static var sidebarBg: Color { isLight ? Light.sidebarBg : Dark.sidebarBg }
    static var sidebarHover: Color { isLight ? Light.sidebarHover : Dark.sidebarHover }
    static var sidebarActive: Color { isLight ? Light.sidebarActive : Dark.sidebarActive }

    // ─── Text ────────────────────────────────────────────────────
    static var fg: Color { isLight ? Light.fg : Dark.fg }
    static var muted: Color { isLight ? Light.muted : Dark.muted }
    static var accentFg: Color { isLight ? Light.accentFg : Dark.accentFg }

    // ─── Accent ──────────────────────────────────────────────────
    static var accent: Color { isLight ? Light.accent : Dark.accent }
    static var accentSoft: Color { accent.opacity(isLight ? 0.14 : 0.15) }

    // ─── Borders ─────────────────────────────────────────────────
    static var border: Color { isLight ? Light.border : Dark.border }
    static var borderBright: Color { isLight ? Light.borderBright : Dark.borderBright }

    // ─── Semantic ────────────────────────────────────────────────
    static var success: Color { isLight ? Light.success : Dark.success }
    static var warning: Color { isLight ? Light.warning : Dark.warning }
    static var error: Color { isLight ? Light.error : Dark.error }

    // ─── Shadows ─────────────────────────────────────────────────
    static var cardShadow: Shadow { isLight ? Light.cardShadow : Dark.cardShadow }
    static var popoverShadow: Shadow { isLight ? Light.popoverShadow : Dark.popoverShadow }

    // ─── Radii ───────────────────────────────────────────────────
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusXl: CGFloat = 20
}

// MARK: - Dark palette
extension Theme {
    enum Dark {
        static let bg            = Color(hex: "#191816")
        static let surface       = Color(hex: "#23211e")
        static let sidebarBg     = Color(hex: "#141311")
        static let sidebarHover  = Color(hex: "#23211e")
        static let sidebarActive = Color(hex: "#3a8b80").opacity(0.12)

        static let fg            = Color(hex: "#edebe5")
        static let muted         = Color(hex: "#8f8b80")
        static let accentFg      = Color(hex: "#0d0c0a")

        static let accent        = Color(hex: "#56b0a4")

        static let border        = Color(hex: "#33312b")
        static let borderBright  = Color(hex: "#525557")

        static let success       = Color(hex: "#4caf50")
        static let warning       = Color(hex: "#f6a83a")
        static let error         = Color(hex: "#e57373")

        static let cardShadow    = Shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        static let popoverShadow = Shadow(color: .black.opacity(0.3), radius: 24, y: 0)
    }
}

// MARK: - Light palette
extension Theme {
    enum Light {
        static let bg            = Color(hex: "#f6f5f1")
        static let surface       = Color(hex: "#ffffff")
        static let sidebarBg     = Color(hex: "#f0efe9")
        static let sidebarHover  = Color(hex: "#e8e6de")
        static let sidebarActive = Color(hex: "#3a8b80").opacity(0.10)

        static let fg            = Color(hex: "#1e1d1a")
        static let muted         = Color(hex: "#88847a")
        static let accentFg      = Color(hex: "#ffffff")

        static let accent        = Color(hex: "#3a8b80")

        static let border        = Color(hex: "#e4e2da")
        static let borderBright  = Color(hex: "#d0cdc4")

        static let success       = Color(hex: "#4caf50")
        static let warning       = Color(hex: "#f6a83a")
        static let error         = Color(hex: "#e57373")

        static let cardShadow    = Shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        static let popoverShadow = Shadow(color: .black.opacity(0.08), radius: 16, y: 4)
    }
}

// MARK: - Shadow helper
struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

extension View {
    func dropShadow(_ shadow: Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

// MARK: - Hex Color Extension
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

// MARK: - Theme environment key
private struct ThemeSchemeKey: EnvironmentKey {
    static let defaultValue: Bool = false  // false = dark (default)
}

extension EnvironmentValues {
    var isLightTheme: Bool {
        get { self[ThemeSchemeKey.self] }
        set { self[ThemeSchemeKey.self] = newValue }
    }
}
