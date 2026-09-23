// ios/App/Stark/Stark/SigilKeyboardToolbar.swift
import SwiftUI
import StarkKit

/// A row of one-tap `+` `@` `%` `~` buttons above the keyboard (issue #104), so typing a tag
/// doesn't mean switching to the symbol pages. Applies to whichever tag-aware text field has
/// focus: `isVisible` is false while a field that must not get tags (the URL field) is focused,
/// which leaves the keyboard's accessory row empty. `onTap` receives the sigil; the screen
/// decides which field to append to (`TagAutocomplete.appending`).
///
/// A keyboard-placement toolbar is simply never shown without an on-screen keyboard, so this
/// needs no `#if targetEnvironment(macCatalyst)`.
struct SigilKeyboardToolbar: ToolbarContent {
    let isVisible: Bool
    let onTap: (Character) -> Void

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItemGroup(placement: .keyboard) { buttons }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItemGroup(placement: .keyboard) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if isVisible {
            ForEach(TagAutocomplete.allSigils, id: \.self) { sigil in
                Button {
                    onTap(sigil)
                } label: {
                    Text(String(sigil))
                        .font(Fonts.mono(20, weight: .semibold))
                        .foregroundStyle(Colors.text)
                        .frame(width: 56, height: 32)
                        .background(Colors.separator)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Insert \(String(sigil))")
                if sigil != TagAutocomplete.allSigils.last { Spacer() }
            }
        }
    }
}
