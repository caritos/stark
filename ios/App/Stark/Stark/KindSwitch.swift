// ios/App/Stark/Stark/KindSwitch.swift
import SwiftUI

/// Which kind of item the add/edit form describes.
enum ItemKind: String, CaseIterable { case event = "Event", reminder = "Reminder" }

/// Event / Reminder switch: a rounded segmented control (system segmented look) with the chosen
/// segment filled with the accent. Shared by Add (issue #109) and Edit, where switching converts
/// the item (issue #116).
struct KindSwitch: View {
    @Binding var kind: ItemKind

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ItemKind.allCases, id: \.self) { option in
                let selected = option == kind
                Button {
                    kind = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Colors.text)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? Colors.accent : Color.clear))
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Colors.card))
    }
}
