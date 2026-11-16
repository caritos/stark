import SwiftUI
import StarkKit

/// The hamburger's menu: the calendar views (a checkmark on the current one), a divider, Settings.
/// Shown in a popover anchored to the bar's hamburger button.
struct ViewMenu: View {
    let current: CalendarViewChoice
    let onChoose: (CalendarViewChoice) -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(CalendarViewChoice.allCases, id: \.self) { choice in
                row(title: choice.title, systemImage: choice.systemImage, checked: choice == current) {
                    onChoose(choice)
                }
            }
            Divider().padding(.horizontal, Spacing.md)
            row(title: "Settings", systemImage: "gearshape", checked: false, action: onSettings)
        }
        .padding(.vertical, Spacing.xs)
        .frame(minWidth: 220)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(.regularMaterial)
    }

    private func row(title: String, systemImage: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .frame(width: 24)
                    .foregroundStyle(Colors.accent)
                Text(title)
                    .foregroundStyle(Colors.text)
                Spacer(minLength: Spacing.md)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Colors.accent)
                }
            }
            .padding(.horizontal, Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}
