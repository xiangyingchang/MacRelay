import SwiftUI

// MARK: - Shared iOS Theme Tokens
// Mirrors the Mac App's warm-neutral palette for visual consistency.
// Uses adaptive Color values that respect system light/dark automatically.

enum IOSTheme {
    // Spacing (4px grid, shared with Mac)
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // Radii
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusXl: CGFloat = 20

    // Adaptive Colors (auto dark/light)
    #if os(iOS)
    static let bg = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let surfaceElevated = Color(uiColor: .tertiarySystemBackground)
    static let border = Color(uiColor: .separator)
    #else
    static let bg = Color(NSColor.windowBackgroundColor)
    static let surface = Color(NSColor.controlBackgroundColor)
    static let surfaceElevated = Color(NSColor.underPageBackgroundColor)
    static let border = Color(NSColor.separatorColor)
    #endif
    static let fg = Color.primary
    static let muted = Color.secondary

    // Accent - teal, consistent with Mac app
    static let accent = Color(red: 0.227, green: 0.545, blue: 0.506)
    static let accentSoft = accent.opacity(0.12)
    static let accentFg = Color.white

    // Semantic
    static let success = Color(red: 0.298, green: 0.686, blue: 0.314)
    static let warning = Color(red: 0.965, green: 0.659, blue: 0.227)
    static let error = Color(red: 0.898, green: 0.451, blue: 0.451)

    // Typography - Apple HIG: tracking is size-specific. Dynamic Type supported.
    enum Typography {
        static let titleLarge = Font.system(size: 22, weight: .bold)
        static let title = Font.system(size: 17, weight: .semibold)
        static let bodyLarge = Font.system(size: 16, weight: .regular)
        static let body = Font.system(size: 15, weight: .regular)
        static let bodySmall = Font.system(size: 14, weight: .regular)
        static let label = Font.system(size: 14, weight: .semibold)
        static let labelSmall = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 12, weight: .regular)
        static let captionBold = Font.system(size: 12, weight: .bold)
        static let micro = Font.system(size: 10, weight: .semibold)
        static let mono = Font.system(size: 13, design: .monospaced)
        static let monoSmall = Font.system(size: 11, design: .monospaced)
    }

    // Animation (Apple spring physics)
    enum Animation {
        static let smooth = SwiftUI.Animation.smooth(duration: 0.35, extraBounce: 0)
        static let snappy = SwiftUI.Animation.smooth(duration: 0.25, extraBounce: 0)
        static let spring = SwiftUI.Animation.spring(duration: 0.35, bounce: 0.2)
        static let hover = SwiftUI.Animation.easeOut(duration: 0.15)
    }
}

// MARK: - Press Feedback for iOS
// Apple: respond on touch-down, not touch-up.
extension View {
    func iosPressFeedback(scale: CGFloat = 0.97) -> some View {
        modifier(IOSPressFeedbackModifier(scale: scale))
    }
}

private struct IOSPressFeedbackModifier: ViewModifier {
    let scale: CGFloat
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? scale : 1.0)
            .animation(IOSTheme.Animation.snappy, value: isPressed)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
                isPressed = pressing
            })
    }
}
