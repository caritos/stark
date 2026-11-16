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
    /// The year in the month and year titles.
    static let yearRed = Color(light: 0xFF3B30, dark: 0xFF453A)
    /// Year view heat map, by `DayDensity.level` 1 / 2 / 3: pale yellow, amber, salmon. The dark
    /// values are deep enough to sit on black yet keep `Colors.text` readable.
    static let heatLow = Color(light: 0xFFF6C8, dark: 0x4D4519)
    static let heatMedium = Color(light: 0xF9DE9C, dark: 0x70561A)
    static let heatHigh = Color(light: 0xF2A9A0, dark: 0x83332E)
    /// Full-screen Month: a holiday calendar's all-day chip (pale lilac) and its text (purple).
    static let holidayChip = Color(light: 0xF1E1F7, dark: 0x3A2645)
    static let holidayText = Color(light: 0x8A34A8, dark: 0xD9A8EE)
    /// Full-screen Month: today's whole cell, pale blue.
    static let todayCell = Color(light: 0xE6F0FD, dark: 0x13243D)
    /// Full-screen Month: the outline around the displayed month's block of days.
    static let monthOutline = Color(light: 0x3B82F6, dark: 0x5B9BFF)
    /// Full-screen Month: a reminder's outlined checkbox (Fantastical's red).
    static let reminderBox = Color(light: 0xFF3B30, dark: 0xFF453A)
    /// Full-screen Quarter: the thicker lines between months and under the weekday strip.
    static let quarterSeam = Color(light: 0xD1D1D6, dark: 0x48484A)
    /// Full-screen Quarter: a holiday calendar's thin text-less bar (mid lilac; `holidayChip` is
    /// too pale to read as a 4 pt line).
    static let holidayBar = Color(light: 0xC27BDB, dark: 0x9E5FB8)
    /// Day and Week timelines: the current-time line, its dot and its time label.
    static let nowLine = yearRed
    /// Day and Week timelines: an hour rule.
    static let hourRule = Color(light: 0xE5E5EA, dark: 0x2C2C2E)
    /// Day and Week timelines: a block's fill is its calendar colour at this opacity.
    static let timelineBlockOpacity = 0.18
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

/// A round, glyph-only toolbar button. `isProminent` fills it with the accent (the committing
/// action); otherwise it is a white card circle (glass on iOS 26) for dismiss. A disabled
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

/// The plain view behind `SquareToolbarButton`, for placing the same round button inside another
/// toolbar item (the planner's day chevrons sit in its principal item).
struct SquareButton: View {
    let systemImage: String
    let label: String
    var isProminent = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(label)
    }

    private var glyph: some View {
        let base = Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(glyphColor)
            .frame(width: 40, height: 40)
        return Group {
            if isProminent && !isDisabled {
                base.background(Circle().fill(Colors.accent))
            } else if #available(iOS 26.0, *) {
                base.glassEffect(.regular, in: Circle())
            } else {
                base.background(Circle().fill(Colors.card)
                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5))
            }
        }
        .contentShape(Circle())
    }

    private var glyphColor: Color {
        if isProminent { return isDisabled ? Colors.textSecondary.opacity(0.6) : .white }
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
