// ios/App/Stark/Stark/EditItemView.swift
import SwiftUI
import StarkKit

/// Edit + detail sheet for one agenda row. Editable fields (title, date, repeat) are committed
/// only by Save; the action buttons act immediately and dismiss. Reminders show Done / Undo /
/// Skip This Occurrence / Delete; events show Attended / Didn't Attend / Clear / Remove This
/// Occurrence / Delete.
struct EditItemView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    let item: AgendaItem

    @State private var title: String
    @State private var date: Date
    @State private var recurrence: RecurrenceRule?
    @State private var showDeleteConfirm = false

    /// The date the form started with, used to tell "left alone" from "edited".
    private let initialDate: Date

    init(item: AgendaItem) {
        self.item = item
        let startDate: Date
        let startRecurrence: RecurrenceRule?
        switch item.kind {
        case .event(let event):
            startDate = event.start
            startRecurrence = event.recurrence
        case .reminder(let reminder):
            // For a recurring reminder `dueDate` is the series' anchor, not the tapped
            // occurrence (`item.occurrence`) — editing changes every occurrence.
            startDate = reminder.dueDate ?? item.occurrence
            startRecurrence = reminder.recurrence
        }
        _title = State(initialValue: item.title)
        _date = State(initialValue: startDate)
        _recurrence = State(initialValue: startRecurrence)
        initialDate = startDate
    }

    var body: some View {
        NavigationStack {
            // A plain-style `List`, not `Form`: `Form` on iOS forces inset-grouped rounded
            // cards regardless of `.listStyle`, and the design has no rounded corners.
            List {
                Section {
                    TextField("Title", text: $title)
                    DatePicker(dateLabel, selection: $date, displayedComponents: dateComponents)

                    NavigationLink {
                        RepeatPickerView(recurrence: $recurrence)
                    } label: {
                        HStack {
                            Text("Repeat")
                            Spacer()
                            Text(recurrenceSummary).foregroundStyle(Colors.textSecondary)
                        }
                    }
                } footer: {
                    if item.isRecurring {
                        Text("Changes apply to every occurrence.")
                            .font(.footnote)
                            .foregroundStyle(Colors.textSecondary)
                    }
                }
                .listRowBackground(Colors.background)

                Section {
                    if let actions = eventActions {
                        if actions.showsAttended {
                            Button("Attended") { markOutcome(.attended) }.foregroundStyle(Colors.accent)
                        }
                        if actions.showsDidntAttend {
                            Button("Didn't Attend") { markOutcome(.skipped) }.foregroundStyle(Colors.accent)
                        }
                        if actions.showsClear {
                            Button("Clear") { markOutcome(nil) }.foregroundStyle(Colors.accent)
                        }
                        if actions.showsRemoveOccurrence {
                            Button("Remove This Occurrence") { skipOccurrence() }.foregroundStyle(Colors.accent)
                        }
                    }
                    if showsDone {
                        Button("Done") { markDone() }.foregroundStyle(Colors.accent)
                    }
                    if showsUndo {
                        Button("Undo") { markUndone() }.foregroundStyle(Colors.accent)
                    }
                    if showsSkip {
                        Button("Skip This Occurrence") { skipOccurrence() }.foregroundStyle(Colors.accent)
                    }
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                }
                .listRowBackground(Colors.background)
            }
            // Flat list rows (not inset-grouped rounded cards) to keep hard edges.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Colors.background)
            .listRowSeparatorTint(Colors.separator)
            .navigationTitle(isEvent ? "Event" : "Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.background, for: .navigationBar)
            .toolbar {
                FlatToolbarButton(title: "Cancel", placement: .cancellationAction) { dismiss() }
                FlatToolbarButton(title: "Save", placement: .confirmationAction, isDisabled: trimmedTitle.isEmpty) { save() }
            }
            .confirmationDialog(deleteMessage, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
        }
        .tint(Colors.accent)
        .preferredColorScheme(.dark)
    }

    // MARK: Derived state

    private var isEvent: Bool {
        if case .event = item.kind { return true }
        return false
    }

    private var isAllDayEvent: Bool {
        if case .event(let event) = item.kind { return event.isAllDay }
        return false
    }

    private var dateLabel: String { isEvent ? "Start" : "Due" }

    private var dateComponents: DatePickerComponents {
        isAllDayEvent ? [.date] : [.date, .hourAndMinute]
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recurrenceSummary: String {
        recurrence?.summary ?? "Never"
    }

    /// Reminder, not completed.
    private var showsDone: Bool {
        if case .reminder(let reminder) = item.kind { return !reminder.isCompleted }
        return false
    }

    /// Completed one-off reminder (a recurring occurrence's completed copy is a one-off too).
    private var showsUndo: Bool {
        if case .reminder(let reminder) = item.kind { return reminder.isCompleted && !item.isRecurring }
        return false
    }

    /// Reminders only; a recurring event's equivalent is "Remove This Occurrence" in `eventActions`.
    private var showsSkip: Bool {
        if case .reminder = item.kind { return item.isRecurring && !item.isCompleted }
        return false
    }

    /// Attended / Didn't Attend / Clear / Remove This Occurrence, for events only.
    private var eventActions: EventOutcomeActions? {
        guard case .event = item.kind else { return nil }
        return EventOutcomeActions(outcome: item.outcome, isRecurring: item.isRecurring)
    }

    private var deleteMessage: String {
        item.isRecurring
            ? "This deletes all future occurrences."
            : "This cannot be undone."
    }

    // MARK: Actions

    private func save() {
        switch item.kind {
        case .event(let event):
            // `settingStart` shifts `end` by the same delta so the duration survives the edit.
            var updated = event.settingStart(date)
            updated.title = trimmedTitle
            updated.recurrence = recurrence
            store.updateEvent(updated)
        case .reminder(let reminder):
            var updated = reminder
            updated.title = trimmedTitle
            // A reminder with no due date stays that way unless the user picked one.
            if reminder.dueDate != nil || date != initialDate {
                updated.dueDate = date
            }
            updated.recurrence = recurrence
            store.updateReminder(updated)
        }
        dismiss()
    }

    private func markDone() {
        guard case .reminder(let reminder) = item.kind else { return }
        store.completeReminder(id: reminder.id, on: item.occurrence)
        dismiss()
    }

    private func markUndone() {
        guard case .reminder(let reminder) = item.kind else { return }
        store.uncompleteReminder(id: reminder.id)
        dismiss()
    }

    private func markOutcome(_ outcome: EventOutcome?) {
        guard case .event(let event) = item.kind else { return }
        store.setEventOutcome(id: event.id, on: item.occurrence, outcome: outcome)
        dismiss()
    }

    private func skipOccurrence() {
        switch item.kind {
        case .event(let event): store.skipEvent(id: event.id, on: item.occurrence)
        case .reminder(let reminder): store.skipReminder(id: reminder.id, on: item.occurrence)
        }
        dismiss()
    }

    private func delete() {
        switch item.kind {
        case .event(let event): store.deleteEvent(id: event.id)
        case .reminder(let reminder): store.deleteReminder(id: reminder.id)
        }
        dismiss()
    }
}
