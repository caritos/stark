// ios/App/Stark/Stark/SheetErrorBanner.swift
import SwiftUI
import StarkKit

/// The main screen's error banner (accent strip, tap to dismiss), for sheets: a failed router
/// write shows its `ItemRouterError.message` here and the sheet stays open.
struct SheetErrorBanner: View {
    let text: String
    /// A notice (nothing failed) uses the main screen's notice strip colour, not the accent.
    var isNotice = false
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Colors.text)
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isNotice ? Colors.separator : Colors.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityHint("Dismisses the message.")
    }
}

extension Error {
    /// The sentence a view shows for a failed router call.
    var routerMessage: String {
        (self as? ItemRouterError)?.message ?? localizedDescription
    }
}
