// ios/App/Stark/Stark/QuickAddRow.swift
import SwiftUI
import StarkKit

/// Sits under Add's Title field. While the typed title contains a date, time, repeat or kind
/// (`QuickAddParser`), shows one button with a plain-language summary; tapping it applies the
/// suggestion. Nothing is ever applied automatically. Renders nothing otherwise, so it reserves
/// no space. English only, on this device.
struct QuickAddRow: View {
    let text: String
    let onApply: (QuickAddSuggestion) -> Void

    /// Gregorian whatever calendar the phone uses (as the planner does), in the phone's time zone
    /// and locale (the locale decides the 12 or 24 hour summary).
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = .current
        return calendar
    }

    var body: some View {
        if let suggestion = QuickAddParser.parse(text, now: Date(), calendar: Self.calendar) {
            Button {
                onApply(suggestion)
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                    Text(suggestion.summary)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Text("Apply").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Colors.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apply: \(suggestion.summary)")
            .accessibilityHint("Fills the title, date, time, repeat and kind.")
        }
    }
}
