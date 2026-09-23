// ios/App/Stark/Stark/Theme.swift
import SwiftUI

// Braun/Bauhaus: hard edges, no rounded corners, one accent color, flat geometry.
// Values match mobile/src/theme.ts exactly, so Stark's native app looks identical
// to the Expo app it replaces.
enum Colors {
    static let background = Color(hex: 0x1A1A1A)
    static let accent = Color(hex: 0xE8461A)
    static let text = Color(hex: 0xF0F0F0)
    static let textSecondary = Color(hex: 0x888888)
    static let separator = Color(hex: 0x333333)
    static let checkboxBorder = Color(hex: 0x555555)
    /// A muted purple: a single, deliberate, user-approved exception to the one-accent-color
    /// rule, so a glance tells task days (accent) from event days. Scoped to exactly two places:
    /// the month grid's event density markers (`MonthGridView`) and the year view's day-cell tint
    /// (`YearView`, issue #102 — purple wins when a day has both tasks and events). Don't use it
    /// anywhere else.
    static let eventDot = Color(hex: 0x8E5FD9)
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
}

// JetBrainsMono-Regular.ttf / JetBrainsMono-SemiBold.ttf (bundled in Fonts/, registered via
// UIAppFonts in Info.plist — see App/Stark/Info.plist) cover the only two weights this app
// ever asks for. Titles stay on the default system font.
enum Fonts {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .semibold: return .custom("JetBrainsMono-SemiBold", size: size)
        default: return .custom("JetBrainsMono-Regular", size: size)
        }
    }
}

/// A toolbar button without iOS 26's rounded glass capsule (the design has no rounded
/// corners). Where the API doesn't exist (iOS 17-25) the plain toolbar button is already flat.
struct FlatToolbarButton: ToolbarContent {
    let title: String
    var systemImage: String? = nil
    let placement: ToolbarItemPlacement
    var isDisabled = false
    let action: () -> Void

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: placement) { button }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) { button }
        }
    }

    @ViewBuilder
    private var button: some View {
        if let systemImage {
            Button(title, systemImage: systemImage, action: action).disabled(isDisabled)
        } else {
            Button(title, action: action).disabled(isDisabled)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
