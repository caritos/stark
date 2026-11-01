// ios/App/Stark/Stark/KindSwitch.swift
import SwiftUI

/// Which kind of item the add/edit form describes.
enum ItemKind: String, CaseIterable { case event = "Event", reminder = "Reminder" }

/// Event / Reminder switch: two flat 48 pt squares side by side, the chosen one filled with the
/// accent, the other outlined. Square and flat like the rest of the app (no rounded segments).
/// Shared by Add (issue #109) and Edit, where switching converts the item (issue #116).
struct KindSwitch: View {
    @Binding var kind: ItemKind

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ItemKind.allCases, id: \.self) { option in
                let selected = option == kind
                Button {
                    kind = option
                } label: {
                    Text(option.rawValue)
                        .font(Fonts.mono(15, weight: .semibold))
                        .foregroundStyle(selected ? Colors.background : Colors.text)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(selected ? Colors.accent : Color.clear)
                        .overlay(Rectangle().strokeBorder(selected ? Colors.accent : Colors.checkboxBorder, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
