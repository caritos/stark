import SwiftUI
import StarkKit

/// Fantastical-style floating bar: a round hamburger (view menu) button at left, a centred "All Calendars"
/// pill and a right pill holding Search and Add. Glass on iOS 26, an ultra-thin material capsule
/// on iOS 17+. Every control is at least 44 pt. Content scrolls under it (the lists reserve
/// `FloatingBottomBar.clearance` of bottom margin).
struct FloatingBottomBar: View {
    /// Height of the bar plus its gap to the screen edge: the bottom margin the scrolling
    /// content reserves so its last rows can be scrolled clear of the bar.
    static let clearance: CGFloat = 84

    /// The current mode, read by VoiceOver as the menu button's value.
    let mode: CalendarMode
    /// The full-screen Month or Quarter shown, if any (also read as the menu button's value).
    let full: FullScreenCalendar
    @Binding var showViewMenu: Bool
    let viewMenu: () -> ViewMenu
    let onCalendars: () -> Void
    let onSearch: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button { showViewMenu = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Colors.text)
                    .frame(width: 52, height: 52)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassBackground(Circle())
            .accessibilityLabel("View menu")
            .accessibilityValue(CalendarViewMenu.accessibilityValue(for: mode, full: full))
            .accessibilityHint("Opens the view and settings menu.")
            .popover(isPresented: $showViewMenu) {
                viewMenu().presentationCompactAdaptation(.popover)
            }

            Spacer(minLength: 0)

            Button(action: onCalendars) {
                Text("All Calendars")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Colors.text)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: 52)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassBackground(Capsule())
            .accessibilityLabel("All Calendars")
            .accessibilityHint("Opens the calendar list.")

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Colors.text)
                        .frame(width: 48, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Colors.accent)
                        .frame(width: 48, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add")
            }
            .padding(.horizontal, Spacing.xs)
            .glassBackground(Capsule())
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.xs)
    }
}

private extension View {
    @ViewBuilder
    func glassBackground<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(Colors.separator, lineWidth: 0.5))
        }
    }
}

/// The existing Apple calendar visibility screen (`AppleSettingsView`), in its own sheet.
struct CalendarsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AppleSettingsView()
                .toolbar {
                    SquareToolbarButton(systemImage: "xmark", label: "Close", placement: .cancellationAction) { dismiss() }
                }
        }
    }
}
