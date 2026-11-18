//
//  CalendarSetsSheet.swift
//  Stark
//
//  The sheet behind the bottom bar's calendars button: All Calendars, the saved sets, a way to
//  make a new one, and the Apple calendar list (per-calendar toggles). Thin: the rules are in
//  StarkKit `CalendarSets`, the state in `CalendarSetsModel`.
//

import SwiftUI
import StarkKit

struct CalendarSetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarSetsModel.self) private var model
    @State private var editing: CalendarSet?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(title: "All Calendars", selected: model.isAllCalendars) { model.showAll(); dismiss() }
                    ForEach(model.sets.sets) { set in
                        let selected = model.activeID == set.id
                        row(title: set.name, selected: selected) {
                            model.apply(set.id)
                            if model.message == nil { dismiss() }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { model.delete(set.id) }
                            Button("Edit") { editing = set }
                                .tint(Colors.accent)
                        }
                        .accessibilityAction(named: "Delete") { model.delete(set.id) }
                        .accessibilityAction(named: "Edit") { editing = set }
                    }
                    if let message = model.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Colors.accent)
                    }
                } footer: {
                    Text("Swipe a set to edit or delete it. Sets are kept on this device.")
                        .font(.footnote)
                        .foregroundStyle(Colors.textSecondary)
                }
                .listRowBackground(Colors.card)

                Section {
                    NavigationLink { CalendarSetEditor(editing: nil) } label: {
                        Label("New Set", systemImage: "plus")
                            .foregroundStyle(Colors.accent)
                    }
                    NavigationLink { AppleSettingsView() } label: {
                        Text("Calendar list")
                            .foregroundStyle(Colors.text)
                    }
                    .accessibilityHint("Shows or hides single calendars and lists.")
                }
                .listRowBackground(Colors.card)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Colors.background)
            .navigationDestination(item: $editing) { CalendarSetEditor(editing: $0) }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SquareToolbarButton(systemImage: "xmark", label: "Close", placement: .cancellationAction) { dismiss() }
            }
        }
    }

    private func row(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Colors.text).lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Colors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
