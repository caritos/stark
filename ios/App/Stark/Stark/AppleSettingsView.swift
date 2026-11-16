// ios/App/Stark/Stark/AppleSettingsView.swift
import SwiftUI
import UIKit
import StarkKit

/// Settings > "Apple Calendar and Reminders": the access state (access itself is requested only
/// from the main screen's `AccessRequiredView`), a way back to iOS Settings after a refusal, the
/// default calendar and list for new items (writable ones only), and one toggle per calendar and
/// reminder list grouped by account. The overlay is always on (no switch). Grouping, wording and
/// which controls show are StarkKit (`AppleSettings`, `DefaultDestination`, tested there); this
/// view only lays them out.
struct AppleSettingsView: View {
    @Environment(AppleOverlayModel.self) private var overlay
    @Environment(DefaultDestinationModel.self) private var destinations
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
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
                Text("Stark shows your Apple calendars and reminders and saves your changes to them. Stark doesn't copy them into its own files or send them anywhere.")
                    .font(.footnote)
                    .foregroundStyle(Colors.textSecondary)
            }
            .listRowBackground(Colors.card)

            if overlay.access == .granted {
                Section {
                    Picker("Default calendar", selection: calendarBinding) {
                        ForEach(destinations.calendarChoices) { calendar in
                            Text(calendar.title).tag(calendar.id)
                        }
                    }
                    .foregroundStyle(Colors.text)
                    Picker("Default list", selection: listBinding) {
                        ForEach(destinations.listChoices) { list in
                            Text(list.title).tag(list.id)
                        }
                    }
                    .foregroundStyle(Colors.text)
                    if let error = destinations.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Colors.accent)
                    }
                } header: {
                    Text("New items")
                } footer: {
                    Text("Events you add in Stark go to the default calendar, to-dos to the default list. Only calendars and lists Stark can change are listed.")
                        .font(.footnote)
                        .foregroundStyle(Colors.textSecondary)
                }
                .listRowBackground(Colors.card)
            }

            if AppleSettings.showsCalendars(isEnabled: overlay.isEnabled, access: overlay.access) {
                ForEach(AppleSettings.groupedByAccount(overlay.calendars)) { group in
                    Section {
                        ForEach(group.calendars) { calendar in
                            Toggle(isOn: shownBinding(calendar.id)) {
                                AppleCalendarToggleLabel(calendar: calendar)
                            }
                            .disabled(isLocked(calendar.id))
                        }
                    } header: {
                        Text(group.accountName)
                    } footer: {
                        if group.calendars.contains(where: { isLocked($0.id) }) {
                            Text("The default calendar and list are always shown, so items you add in Stark stay in view.")
                                .font(.footnote)
                                .foregroundStyle(Colors.textSecondary)
                        }
                    }
                    .listRowBackground(Colors.card)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Colors.background)
        .listRowSeparatorTint(Colors.separator)
        .navigationTitle("Apple Calendar and Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private func isLocked(_ id: String) -> Bool {
        AppleSettings.isLockedOn(id, calendarID: destinations.calendarID, listID: destinations.listID)
    }

    private func refresh() async {
        await overlay.refreshAccess()
        await destinations.refresh()
    }

    /// "" while nothing is resolved (no matching tag: the picker shows nothing chosen).
    private var calendarBinding: Binding<String> {
        Binding(get: { destinations.calendarID ?? "" }, set: { destinations.chooseCalendar($0) })
    }

    private var listBinding: Binding<String> {
        Binding(get: { destinations.listID ?? "" }, set: { destinations.chooseList($0) })
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
            RoundedRectangle(cornerRadius: 3)
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
