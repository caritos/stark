// ios/App/Stark/Stark/Theme.swift
import SwiftUI

// Fantastical-style: system-grouped look, adaptive light/dark tokens that follow the phone's
// appearance (nothing forces a colour scheme), one blue accent, white cards on a grey ground.
enum Colors {
    /// The grouped ground behind cards.
    static let background = Color(light: 0xF2F2F7, dark: 0x000000)
    /// Card / row surface sitting on `background`.
    static let card = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let accent = Color(light: 0x3B82F6, dark: 0x5B9BFF)
    static let text = Color(light: 0x1C1C1E, dark: 0xF2F2F7)
    static let textSecondary = Color(hex: 0x8E8E93)
    static let separator = Color(light: 0xD1D1D6, dark: 0x38383A)
    static let checkboxBorder = Color(light: 0xC7C7CC, dark: 0x636366)
    /// A muted purple for event markers (month grid, year view, planner event blocks) until
    /// stages 2-3 of the redesign replace it.
    static let eventDot = Color(hex: 0x8E5FD9)
}

extension Color {
    /// An appearance-adaptive colour from two 0xRRGGBB values.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            let v = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                           green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
}

// System font with monospaced digits (times and day numbers keep their alignment). The name
// `mono` is kept so call sites need no edit; a rename is a later cleanup.
enum Fonts {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

/// A square, flat, glyph-only toolbar button (no glass capsule, no rounded corners), in the same
/// visual family as the floating Add/Search/Settings buttons. `isProminent` fills it with the
/// accent (the committing action); otherwise it is a neutral dark square (dismiss). A disabled
/// prominent button drops to the neutral fill with a dimmed glyph. `label` is the VoiceOver name,
/// since there is no visible text.
struct SquareToolbarButton: ToolbarContent {
    let systemImage: String
    let label: String
    let placement: ToolbarItemPlacement
    var isProminent = false
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

    private var button: some View {
        SquareButton(systemImage: systemImage, label: label, isProminent: isProminent,
                     isDisabled: isDisabled, action: action)
    }
}

/// An empty, invisible 40 pt square in a toolbar slot, so the items beside it do not shift when
/// a `SquareToolbarButton` is left out (the planner's chevrons stay put on a view-only day).
struct SquareToolbarPlaceholder: ToolbarContent {
    let placement: ToolbarItemPlacement

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: placement) { square }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) { square }
        }
    }

    private var square: some View {
        Color.clear.frame(width: 40, height: 40).accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// The plain view behind `SquareToolbarButton`, for placing the same flat square inside another
/// toolbar item (the planner's day chevrons sit in its principal item).
struct SquareButton: View {
    let systemImage: String
    let label: String
    var isProminent = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: 40, height: 40)
                .background(fillColor)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(label)
    }

    private var fillColor: Color {
        isProminent && !isDisabled ? Colors.accent : Colors.separator
    }

    private var glyphColor: Color {
        if isProminent { return isDisabled ? Colors.textSecondary : Colors.background }
        return Colors.text
    }
}

extension Color {
    /// `0xRRGGBB`. Only theme tokens use it, plus an Apple calendar's own colour (data, not
    /// styling) on overlay rows.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
