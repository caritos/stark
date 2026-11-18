//
//  CalendarSetEditor.swift
//  Stark
//
//  Name and calendars of one set. Errors come from `CalendarSetError.message`, shown inline.
//

import SwiftUI
import StarkKit

struct CalendarSetEditor: View {
    let editing: CalendarSet?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppleOverlayModel.self) private var overlay
    @Environment(CalendarSetsModel.self) private var model
    @State private var name = ""
    @State private var included: Set<String> = []
    @State private var error: CalendarSetError?
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                TextField("Name", text: $name)
                    .foregroundStyle(Colors.text)
                    .accessibilityLabel("Set name")
                if let error {
                    Text(error.message)
                        .font(.footnote)
                        .foregroundStyle(Colors.accent)
                }
            }
            .listRowBackground(Colors.card)

            ForEach(AppleSettings.groupedByAccount(overlay.calendars)) { group in
                Section(group.accountName) {
                    ForEach(group.calendars) { calendar in
                        Toggle(isOn: binding(calendar.id)) {
                            AppleCalendarToggleLabel(calendar: calendar)
                        }
                        .disabled(locked(calendar.id))
                    }
                }
                .listRowBackground(Colors.card)
            }

            if !model.alwaysShown.isEmpty {
                Section {} footer: {
                    Text("The default calendar and list are always shown, so items you add in Stark stay in view.")
                        .font(.footnote)
                        .foregroundStyle(Colors.textSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Colors.background)
        .navigationTitle(editing == nil ? "New Set" : "Edit Set")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).foregroundStyle(Colors.accent)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = editing?.name ?? ""
            // A new set starts from what is shown now; an edited one from its saved calendars.
            // Ids of calendars that no longer exist are dropped, so a save never keeps a stale one.
            included = (editing?.includedIDs ?? model.shownIDs).intersection(model.allIDs)
        }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { locked(id) || included.contains(id) },
                set: { on in
                    if on { included.insert(id) } else { included.remove(id) }
                })
    }

    /// The default calendar and list show locked on, as in Settings: a set cannot hide them.
    private func locked(_ id: String) -> Bool { model.alwaysShown.contains(id) }

    private func save() {
        error = model.save(id: editing?.id, name: name, included: included)
        if error == nil { dismiss() }
    }
}
