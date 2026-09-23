// ios/App/Stark/Stark/TagSuggestionRow.swift
import SwiftUI
import StarkKit

/// Sits directly under a text field. Appears only while the field's text ends in a
/// `+`/`@`/`%`/`~`-prefixed partial word (`TagAutocomplete.currentPrefix`), showing every
/// already-used matching token as a tappable chip; tapping one completes the word in place.
/// Renders nothing (not even empty space) when there's no active prefix or no matches, so it
/// never reserves layout it isn't using.
struct TagSuggestionRow: View {
    @EnvironmentObject private var store: PlannerStore
    let text: String
    let onApply: (String) -> Void

    private var suggestions: [String] {
        guard let prefix = TagAutocomplete.currentPrefix(in: text) else { return [] }
        return TagAutocomplete.suggestions(for: prefix, events: store.events, reminders: store.reminders)
    }

    var body: some View {
        let matches = suggestions
        if !matches.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(matches, id: \.self) { tag in
                        Button {
                            onApply(tag)
                        } label: {
                            Text(tag)
                                .font(Fonts.mono(13))
                                .foregroundStyle(Colors.text)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(Colors.separator)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
