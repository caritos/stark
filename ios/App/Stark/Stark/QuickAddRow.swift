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

    var body: some View {
        if let suggestion = QuickAddParser.parse(text, now: Date(), calendar: .current) {
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
            .accessibilityHint("Fills in the date, time and repeat from your title.")
        }
    }
}
