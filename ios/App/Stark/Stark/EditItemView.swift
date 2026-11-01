// ios/App/Stark/Stark/EditItemView.swift
import SwiftUI
import StarkKit

/// Edit + detail sheet for one agenda row. Editable fields (title, date, all-day, end for timed
/// events, repeat, repeat end, notes, location and URL for events, priority for reminders) are
/// committed only by Save; the action buttons act immediately and dismiss. Reminders show Done /
/// Undo / Skip / Delete; events show Done / Skip / Undo / Remove
/// This Occurrence / Open Link (for an http/https URL, does not dismiss) / Delete.
///
/// The Event / Reminder switch above the form converts the item (issue #116): the form switches
/// to the other kind's fields at once, but nothing is stored until Save, which replaces the item
/// under the same id in one store call (`PlannerStore.convertEvent` / `convertReminder`). While
/// converting, the per-occurrence actions and History (which belong to the old kind) are hidden.
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
    /// The kind the form describes; differs from the item's own kind while converting.
    @State private var kind: ItemKind
    @State private var showMarksConfirm = false

    /// Which text field has focus, so the keyboard's sigil buttons know which one to append to
    /// (and stay hidden for the URL field, which must not get tags).
    private enum Field { case title, location, url, notes }
    @FocusState private var focusedField: Field?

    /// The date and all-day flag the form started with, used to tell "left alone" from "edited".
    private let initialDate: Date
    private let initialAllDay: Bool
    /// One stable "today" for the history stats, captured when the sheet is created.
    private let sheetToday = Date()

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
        if case .event = item.kind { _kind = State(initialValue: .event) } else { _kind = State(initialValue: .reminder) }
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
                    if isEvent {
                        DatePicker("Ends", selection: $endDate, in: date...,
                                   displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
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
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if item.isRecurring {
                            Text("Changes apply to every occurrence.")
                        }
                        if movesDetailsToNotes {
                            Text("Location and URL will be added to the notes.")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(Colors.textSecondary)
                }
                .listRowBackground(Colors.background)

                if !isConverting, let history, !history.entries.isEmpty {
                    Section("History") {
                        ForEach(Array(history.summaryLines().enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Fonts.mono(13))
                                .foregroundStyle(Colors.textSecondary)
                        }
                    }
                    .listRowBackground(Colors.background)
                }

                Section {
                    if !isConverting, let actions = eventActions {
                        if actions.showsAttended {
                            Button("Done") { markOutcome(.attended) }.foregroundStyle(Colors.accent)
                        }
                        if actions.showsDidntAttend {
                            Button("Skip") { markOutcome(.skipped) }.foregroundStyle(Colors.accent)
                        }
                        if actions.showsClear {
                            Button("Undo") { markOutcome(nil) }.foregroundStyle(Colors.accent)
                        }
                        if actions.showsRemoveOccurrence {
                            Button("Remove This Occurrence") { skipOccurrence() }.foregroundStyle(Colors.accent)
                        }
                    }
                    if !isConverting, let link = openableLink {
                        // Opens the link and leaves the sheet up: nothing is dismissed or saved.
                        Button("Open Link") { openURL(link) }.foregroundStyle(Colors.accent)
                    }
                    if !isConverting && showsDone {
                        Button("Done") { markDone() }.foregroundStyle(Colors.accent)
                    }
                    if !isConverting && showsUndo {
                        Button("Undo") { markUndone() }.foregroundStyle(Colors.accent)
                    }
                    if !isConverting && showsSkip {
                        Button("Skip") { skipOccurrence() }.foregroundStyle(Colors.accent)
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
            .sigilKeyboardBar(isVisible: focusedField != nil && focusedField != .url,
                              onTap: insertSigil)
            // Same pinned switch as Add (issue #109); only for an event or an open reminder.
            .safeAreaInset(edge: .top, spacing: 0) {
                if canConvert {
                    KindSwitch(kind: kindSelection)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Colors.background)
                }
            }
            .alert("Convert to Reminder?", isPresented: $showMarksConfirm) {
                Button("Convert", role: .destructive) { kind = .reminder }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(marksMessage)
            }
            .navigationTitle(kind.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.background, for: .navigationBar)
            .toolbar {
                SquareToolbarButton(systemImage: "checkmark", label: "Save", placement: .confirmationAction,
                                    isProminent: true, isDisabled: trimmedTitle.isEmpty) { save() }
                SquareToolbarButton(systemImage: "xmark", label: "Cancel", placement: .cancellationAction) { dismiss() }
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

    /// Completion / attendance history for this item (recomputed from the store each render).
    private var history: CompletionHistory? {
        switch item.kind {
        case .reminder(let reminder):
            return CompletionHistory.forReminder(reminder, among: store.reminders, today: sheetToday)
        case .event(let event):
            return CompletionHistory.forEvent(event, today: sheetToday)
        }
    }

    /// The form's kind (the converted one while converting), which decides the fields shown.
    private var isEvent: Bool { kind == .event }

    /// The item's own kind, before any conversion.
    private var originalKind: ItemKind {
        if case .event = item.kind { return .event }
        return .reminder
    }

    private var isConverting: Bool { kind != originalKind }

    /// An event, or an open reminder: a completed one (or a series' completed copy) is history.
    private var canConvert: Bool {
        switch item.kind {
        case .event: return true
        case .reminder(let reminder): return ItemConversion.isConvertible(reminder)
        }
    }

    /// Attended/skipped marks an event would lose by becoming a reminder.
    private var droppedMarks: Int {
        if case .event(let event) = item.kind { return ItemConversion.droppedMarks(converting: event) }
        return 0
    }

    private var marksMessage: String {
        let marks = droppedMarks == 1 ? "1 attended/skipped mark" : "\(droppedMarks) attended/skipped marks"
        return "This event has \(marks). A reminder can't keep them, so they will be removed when you save."
    }

    /// Event -> reminder with a location or URL typed: those move into the notes on save.
    private var movesDetailsToNotes: Bool {
        isConverting && originalKind == .event
            && (FormFields.trimmedOrNil(location) != nil || FormFields.trimmedOrNil(url) != nil)
    }

    /// The switch's binding: choosing Reminder for an event with marks asks first (on the tap,
    /// so the user learns before editing anything else); cancelling leaves it an event.
    private var kindSelection: Binding<ItemKind> {
        Binding(
            get: { kind },
            set: { newKind in
                if newKind == .reminder && kind == .event && originalKind == .event && droppedMarks > 0 {
                    showMarksConfirm = true
                } else {
                    kind = newKind
                }
            }
        )
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

    /// Done / Skip / Undo / Remove This Occurrence, for events only.
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
        switch (item.kind, kind) {
        case (.event(let event), .event):
            store.updateEvent(edited(event))
        case (.reminder(let reminder), .reminder):
            store.updateReminder(edited(reminder))
        case (.event(let event), .reminder):
            // Apply the form to the event, then convert (location/URL go into the notes, the end
            // and marks are dropped), then the reminder-only field: one store call, one write each.
            var converted = ItemConversion.reminder(from: edited(event))
            converted.priority = priority.icalValue
            store.convertEvent(id: event.id, to: converted)
        case (.reminder(let reminder), .event):
            // Priority is dropped; the form's Starts/Ends/All day and Location/URL apply (an
            // undated reminder lands all-day).
            var converted = ItemConversion.event(fromEdited: edited(reminder), originalDueDate: reminder.dueDate,
                                                 start: date, end: endDate, allDay: allDay)
            converted.location = FormFields.trimmedOrNil(location)
            converted.url = FormFields.trimmedOrNil(url)
            store.convertReminder(id: reminder.id, to: converted)
        }
        dismiss()
    }

    /// The event with the form's fields applied.
    private func edited(_ event: Event) -> Event {
        // `scheduled` stores the picked start/end (an all-day end is its last day) and drops an
        // end that is not after the start.
        var updated = event.scheduled(start: date, end: endDate, allDay: allDay)
        updated.title = trimmedTitle
        updated.recurrence = repeatEnd.applied(to: recurrence)
        updated.notes = FormFields.trimmedOrNil(notes)
        updated.location = FormFields.trimmedOrNil(location)
        updated.url = FormFields.trimmedOrNil(url)
        return updated
    }

    /// The reminder with the form's fields applied.
    private func edited(_ reminder: Reminder) -> Reminder {
        var updated = reminder
        updated.title = trimmedTitle
        // A reminder with no due date stays that way unless the user picked one.
        if reminder.dueDate != nil || date != initialDate || allDay != initialAllDay {
            updated.dueDate = FormFields.normalizedStart(date, allDay: allDay)
        }
        updated.recurrence = repeatEnd.applied(to: recurrence)
        updated.notes = FormFields.trimmedOrNil(notes)
        updated.priority = ReminderPriority.updated(original: reminder.priority, chosen: priority)
        return updated
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
