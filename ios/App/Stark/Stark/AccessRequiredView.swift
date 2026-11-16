//
//  AccessRequiredView.swift
//  Stark
//
//  Shown on the main screen, above the calendar, while Stark has no full access to Calendar and
//  Reminders. It says what the access is for BEFORE asking: the system prompt appears only when
//  the user taps "Allow Access" (never at launch). After a refusal it points to iOS Settings, the
//  only place to undo it. Stark's own (local) items stay visible below it.
//

import SwiftUI
import UIKit
import StarkKit

struct AccessRequiredView: View {
    @Environment(AppleOverlayModel.self) private var overlay
    @Environment(DefaultDestinationModel.self) private var destinations
    @Environment(\.openURL) private var openURL
    @State private var isAsking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("STARK NEEDS CALENDAR AND REMINDERS")
                .font(Fonts.mono(13, weight: .semibold))
                .foregroundStyle(Colors.text)
                .accessibilityAddTraits(.isHeader)
            Text(explanation)
                .font(.footnote)
                .foregroundStyle(Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if overlay.access == .notAsked {
                Button {
                    ask()
                } label: {
                    Text(isAsking ? "ASKING…" : "ALLOW ACCESS")
                        .font(Fonts.mono(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Colors.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isAsking)
                .accessibilityLabel("Allow access to Calendar and Reminders")
                .accessibilityHint("Shows the iPhone's permission prompt.")
            } else if AppleSettings.showsOpenSettings(overlay.access),
                      let url = URL(string: UIApplication.openSettingsURLString) {
                Button {
                    openURL(url)
                } label: {
                    HStack {
                        Text("Open iOS Settings")
                            .foregroundStyle(Colors.accent)
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .foregroundStyle(Colors.accent)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Stark's page in iOS Settings, where you can allow full access.")
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Colors.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Colors.separator).frame(height: 1)
        }
    }

    /// Plain words: what it is for, what stays on the phone, and what to do now.
    private var explanation: String {
        let purpose = "Stark shows and keeps your events and to-dos in Apple Calendar and Reminders, so they stay in sync with Apple's apps on your devices. Nothing is sent anywhere else."
        switch overlay.access {
        case .notAsked:
            return purpose + " Tap Allow Access, then allow full access to both."
        case .denied:
            return purpose + " Access is off. Turn on full access to Calendars and Reminders for Stark in iOS Settings."
        case .writeOnly:
            return purpose + " Stark can only add, not read. Choose full access for Calendars and Reminders in iOS Settings."
        case .granted:
            return purpose
        }
    }

    private func ask() {
        isAsking = true
        Task {
            await overlay.enable()
            await destinations.refresh()
            isAsking = false
        }
    }
}
