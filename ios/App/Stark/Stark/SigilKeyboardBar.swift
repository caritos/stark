// ios/App/Stark/Stark/SigilKeyboardBar.swift
import SwiftUI
import StarkKit

/// A row of one-tap `+` `@` `%` `~` buttons directly above the keyboard (issue #104), so typing a
/// tag doesn't mean switching to the symbol pages. `onTap` receives the sigil; the screen decides
/// which field to append to (`TagAutocomplete.appending`).
///
/// Deliberately not a `ToolbarItemGroup(placement: .keyboard)`: on iOS 26 that row is drawn with
/// no background, so the form shows through it, and on a real iPhone it did not appear at all.
/// A bottom `safeAreaInset` rides on top of the keyboard's safe area instead and is fully ours to
/// style, so it stays solid and flat like the rest of the app.
struct SigilKeyboardBar: View {
    let onTap: (Character) -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(TagAutocomplete.allSigils, id: \.self) { sigil in
                Button {
                    onTap(sigil)
                } label: {
                    Text(String(sigil))
                        .font(Fonts.mono(22, weight: .semibold))
                        .foregroundStyle(Colors.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Colors.separator)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Insert \(String(sigil))")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Colors.background)
    }
}

/// The Settings toggle for the bar. Off by default (opt-in); stored in `UserDefaults` via
/// `@AppStorage`. The default lives here so Settings and the bar can never disagree.
enum SigilKeyboardSetting {
    static let key = "sigilKeyboardBarEnabled"
    static let defaultValue = false
}

private struct SigilKeyboardBarModifier: ViewModifier {
    let isVisible: Bool
    let onTap: (Character) -> Void
    @AppStorage(SigilKeyboardSetting.key) private var enabled = SigilKeyboardSetting.defaultValue

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if enabled && isVisible { SigilKeyboardBar(onTap: onTap) }
        }
    }
}

extension View {
    /// Shows `SigilKeyboardBar` above the keyboard while `isVisible` (a tag-aware text field has
    /// focus) and the Settings toggle is on. Omitted on Mac Catalyst, which has no on-screen
    /// keyboard.
    @ViewBuilder
    func sigilKeyboardBar(isVisible: Bool, onTap: @escaping (Character) -> Void) -> some View {
        #if targetEnvironment(macCatalyst)
        self
        #else
        modifier(SigilKeyboardBarModifier(isVisible: isVisible, onTap: onTap))
        #endif
    }
}
