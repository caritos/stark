// ios/App/Stark/Stark/EditItemView.swift
import SwiftUI
import StarkKit

/// Edit + detail sheet for one agenda row. Editable fields (title, date, all-day, end for timed
/// events, repeat, repeat end, notes, location and URL for events, priority for reminders) are
/// committed only by Save; the action buttons act immediately and dismiss. Reminders show Done /
/// Undo / Skip This Occurrence / Delete; events show Attended / Didn't Attend / Clear / Remove
/// This Occurrence / Open Link (for an http/https URL, does not dismiss) / Delete.
struct EditItemView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let item: AgendaItem

    @State private var title: String
    @State private var date: Date
    /// Events only. An event with no end starts with Ends equal to Starts, which stores as no end.
    @State private var endDate: Date
    @State private var allDay: Bool
    /// The item's rule without its end (`withoutEnd`); the end is `repeatEnd`, applied on save,
    /// because the repeat presets replace the whole rule and their checkmark compares whole rules.
    @State private var recurrence: RecurrenceRule?
    @State private var repeatEnd: RepeatEnd
    @State private var notes: String
    @State private var location: String
    /// Events only; reminders have no URL.
    @State private var url: String
    @State private var priority: ReminderPriority
    @State private var showDeleteConfirm = false

    /// Which text field has focus, so the keyboard's sigil buttons know which one to append to
    /// (and stay hidden for the URL field, which must not get tags).
    private enum Field { case title, location, url, notes }
    @FocusState private var focusedField: Field?

    /// The date and all-day flag the form started with, used to tell "left alone" from "edited".
    private let initialDate: Date
    private let initialAllDay: Bool

    init(item: AgendaItem) {
        self.item = item
        let startDate: Date
        let startEnd: Date
        let startAllDay: Bool
        let startRecurrence: RecurrenceRule?
        let startNotes: String
        let startLocation: String
        let startURL: String
        let startPriority: ReminderPriority
        switch item.kind {
        case .event(let event):
            startDate = event.start
            // Switching from all-day to timed drops the end (see `Event.scheduled`), so an
            // all-day event's own end is not offered as the timed one.
            startEnd = EventSchedule.formEnd(for: event)
            startAllDay = event.isAllDay
            startRecurrence = event.recurrence
            startNotes = event.notes ?? ""
            startLocation = event.location ?? ""
            startURL = event.url ?? ""
            startPriority = .none
        case .reminder(let reminder):
            // For a recurring reminder `dueDate` is the series' anchor, not the tapped
            // occurrence (`item.occurrence`) — editing changes every occurrence.
            startDate = reminder.dueDate ?? item.occurrence
            startEnd = startDate
            startAllDay = FormFields.isAllDay(reminder)
            startRecurrence = reminder.recurrence
            startNotes = reminder.notes ?? ""
            startLocation = ""
            startURL = ""
            startPriority = ReminderPriority(icalValue: reminder.priority)
        }
        _title = State(initialValue: item.title)
        _date = State(initialValue: startDate)
        _endDate = State(initialValue: startEnd)
        _allDay = State(initialValue: startAllDay)
        _recurrence = State(initialValue: startRecurrence?.withoutEnd)
        _repeatEnd = State(initialValue: RepeatEnd(rule: startRecurrence))
        _notes = State(initialValue: startNotes)
        _location = State(initialValue: startLocation)
        _url = State(initialValue: startURL)
        _priority = State(initialValue: startPriority)
        initialDate = startDate
        initialAllDay = startAllDay
    }

    var body: some View {
        NavigationStack {
            // A plain-style `List`, not `Form`: `Form` on iOS forces inset-grouped rounded
            // cards regardless of `.listStyle`, and the design has no rounded corners.
            List {
                Section {
                    TextField("Title", text: $title)
                        .focused($focusedField, equals: .title)
                    TagSuggestionRow(text: title) { title = TagAutocomplete.applying($0, to: title) }
                    DatePicker(dateLabel, selection: $date,
                               displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                        .onChange(of: date) { oldValue, newValue in
                            // Moving the start moves the end with it, so the duration is kept.
                            endDate = EventSchedule.shiftedEnd(endDate, oldStart: oldValue, newStart: newValue)
                            // A repeat end never precedes the start's day.
                            repeatEnd = repeatEnd.clamped(toStartOn: newValue)
                        }
                    if isEvent && !allDay {
                        DatePicker("Ends", selection: $endDate, in: date...,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                    Toggle("All day", isOn: $allDay)

                    NavigationLink {
                        RepeatPickerView(recurrence: $recurrence)
                    } label: {
                        HStack {
                            Text("Repeat")
                            Spacer()
                            Text(recurrenceSummary).foregroundStyle(Colors.textSecondary)
                        }
                    }

                    if recurrence != nil {
                        NavigationLink {
                            RepeatEndPickerView(end: $repeatEnd, startDate: date)
                        } label: {
                            HStack {
                                Text("Repeat End")
                                Spacer()
                                Text(repeatEnd.summary).foregroundStyle(Colors.textSecondary)
                            }
                        }
                    }

                    if isEvent {
                        TextField("Location", text: $location)
                            .focused($focusedField, equals: .location)
                        TagSuggestionRow(text: location) { location = TagAutocomplete.applying($0, to: location) }
                        TextField("URL", text: $url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .url)
                    }
                    if !isEvent {
                        // A segmented picker drops its label on iOS, so it is shown by the row.
                        LabeledContent("Priority") {
                            Picker("Priority", selection: $priority) {
                                ForEach(ReminderPriority.allCases, id: \.self) { Text($0.pickerLabel) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($focusedField, equals: .notes)
                    TagSuggestionRow(text: notes) { notes = TagAutocomplete.applying($0, to: notes) }
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
                    if let link = openableLink {
                        // Opens the link and leaves the sheet up: nothing is dismissed or saved.
                        Button("Open Link") { openURL(link) }.foregroundStyle(Colors.accent)
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
            .onChange(of: recurrence) { _, newValue in
                // Repeat = Never resets the end.
                if newValue == nil { repeatEnd = .never }
            }
            .task {
                // Full-history corpus for tag suggestions (`+`/`@`/`%`/`~`); non-blocking --
                // suggestions simply improve as more months finish loading, same as Search.
                await store.loadAllMonths()
            }
            .navigationTitle(isEvent ? "Event" : "Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.background, for: .navigationBar)
            .toolbar {
                FlatToolbarButton(title: "Cancel", placement: .cancellationAction) { dismiss() }
                FlatToolbarButton(title: "Save", placement: .confirmationAction, isDisabled: trimmedTitle.isEmpty) { save() }
                SigilKeyboardToolbar(isVisible: focusedField != nil && focusedField != .url,
                                     onTap: insertSigil)
            }
            .confirmationDialog(deleteMessage, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
        }
        .tint(Colors.accent)
        .preferredColorScheme(.dark)
    }

    private func insertSigil(_ sigil: Character) {
        switch focusedField {
        case .title: title = TagAutocomplete.appending(sigil, to: title)
        case .location: location = TagAutocomplete.appending(sigil, to: location)
        case .notes: notes = TagAutocomplete.appending(sigil, to: notes)
        case .url, nil: break
        }
    }

    // MARK: Derived state

    private var isEvent: Bool {
        if case .event = item.kind { return true }
        return false
    }

    private var dateLabel: String { isEvent ? "Starts" : "Due" }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recurrenceSummary: String {
        recurrence?.summary ?? "Never"
    }

    /// Events only: the typed URL when it is a well-formed http or https link, else nil.
    private var openableLink: URL? {
        guard isEvent,
              let link = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = link.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = link.host(percentEncoded: false), !host.isEmpty
        else { return nil }
        return link
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
            // `scheduled` takes the picked start/end for a timed event, and for an all-day one
            // stores the start of the day and drops `end` when switching between all-day and timed.
            var updated = event.scheduled(start: date, end: EventSchedule.storedEnd(endDate, start: date), allDay: allDay)
            updated.title = trimmedTitle
            updated.recurrence = repeatEnd.applied(to: recurrence)
            updated.notes = FormFields.trimmedOrNil(notes)
            updated.location = FormFields.trimmedOrNil(location)
            updated.url = FormFields.trimmedOrNil(url)
            store.updateEvent(updated)
        case .reminder(let reminder):
            var updated = reminder
            updated.title = trimmedTitle
            // A reminder with no due date stays that way unless the user picked one.
            if reminder.dueDate != nil || date != initialDate || allDay != initialAllDay {
                updated.dueDate = FormFields.normalizedStart(date, allDay: allDay)
            }
            updated.recurrence = repeatEnd.applied(to: recurrence)
            updated.notes = FormFields.trimmedOrNil(notes)
            updated.priority = ReminderPriority.updated(original: reminder.priority, chosen: priority)
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
