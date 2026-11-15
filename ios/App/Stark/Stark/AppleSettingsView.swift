// ios/App/Stark/Stark/AppleSettingsView.swift
import SwiftUI
import UIKit
import StarkKit

/// Settings > "Apple Calendar and Reminders": the overlay's on/off switch (the only place access
/// is requested), the access state, a way back to iOS Settings after a refusal, and one toggle
/// per calendar and reminder list grouped by account. Grouping, wording and which controls show
/// are StarkKit (`AppleSettings`, tested there); this view only lays them out.
struct AppleSettingsView: View {
    @Environment(AppleOverlayModel.self) private var overlay
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                Toggle("Show Apple Calendar and Reminders", isOn: enabledBinding)
                    .foregroundStyle(Colors.text)
                LabeledContent("Access") {
                    Text(AppleSettings.statusLabel(overlay.access))
                }
                Text(AppleSettings.statusText(overlay.access))
                    .font(.footnote)
                    .foregroundStyle(Colors.textSecondary)
                if AppleSettings.showsOpenSettings(overlay.access),
                   let url = URL(string: UIApplication.openSettingsURLString) {
                    Button("Open iOS Settings") { openURL(url) }
                        .foregroundStyle(Colors.accent)
                }
            } footer: {
                Text("Shows your Apple calendars and reminders in Stark, read-only. Stark doesn't copy or send them anywhere.")
                    .font(.footnote)
                    .foregroundStyle(Colors.textSecondary)
            }
            .listRowBackground(Colors.background)

            if AppleSettings.showsCalendars(isEnabled: overlay.isEnabled, access: overlay.access) {
                ForEach(AppleSettings.groupedByAccount(overlay.calendars)) { group in
                    Section {
                        ForEach(group.calendars) { calendar in
                            Toggle(isOn: shownBinding(calendar.id)) {
                                AppleCalendarToggleLabel(calendar: calendar)
                            }
                        }
                    } header: {
                        Text(group.accountName)
                    }
                    .listRowBackground(Colors.background)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Colors.background)
        .listRowSeparatorTint(Colors.separator)
        .navigationTitle("Apple Calendar and Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await overlay.refreshAccess() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await overlay.refreshAccess() } }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { overlay.isEnabled },
            set: { on in
                if on {
                    Task { await overlay.enable() }
                } else {
                    overlay.disable()
                }
            })
    }

    private func shownBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { overlay.selection.isShown(id) },
            set: { overlay.setShown(id, $0) })
    }
}

/// A calendar's toggle label: a square in the calendar's own colour (data, the one non-token
/// colour, as on `AppleSourceLabel`), its title, and "Reminders" under a reminder list.
private struct AppleCalendarToggleLabel: View {
    let calendar: AppleCalendarInfo

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Rectangle()
                .fill(calendar.colorRGB.map { Color(hex: $0) } ?? Colors.textSecondary)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.title)
                    .foregroundStyle(Colors.text)
                    .lineLimit(1)
                if calendar.isReminderList {
                    Text("Reminders")
                        .font(.footnote)
                        .foregroundStyle(Colors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
