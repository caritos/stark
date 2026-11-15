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
/// (`ItemRouter.convertEvent` / `convertReminder`). While converting, the per-occurrence actions
/// and History (which belong to the old kind) are hidden.
///
/// Every write goes through `ItemRouter`: Stark's own items go to the local store as before;
/// Apple items (`details` set, loaded by `AppleItemEditor`) are diffed against the stored item's
/// form baseline, so only the fields the owner changed are written (spec call 5). Apple items
/// show no History, no reminder Skip (Apple Reminders can't skip one occurrence), and a repeat
/// Stark can't represent is shown read-only. A failed write shows its message in the sheet's
/// banner and the sheet stays open.
struct EditItemView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.itemRouter) private var router
    @Environment(AppleOverlayModel.self) private var overlay
    let item: AgendaItem
    /// The stored Apple item this sheet edits (`ItemRouter.details`), nil for Stark's own items.
    /// Its form baseline is the `original` every Apple update diffs against (spec call 5).
    let details: ItemDetails?

    /// The editable fields; the logic that turns them back into an item is StarkKit's.
    @State private var form: ItemEditForm
    @State private var showDeleteConfirm = false
    /// The kind the form describes; differs from the item's own kind while converting.
    @State private var kind: ItemKind
    @State private var showMarksConfirm = false
    /// A router failure, shown in the sheet's banner; the sheet stays open.
    @State private var errorMessage: String?
    /// A notice shown in the sheet (the main screen's strip would be hidden under it).
    @State private var noticeMessage: String?
    @State private var isWorking = false
    /// A repeat change on a series with occurrences edited in Calendar: asked before resending.
    @State private var showRuleChangeConfirm = false
    /// Converting an Apple event with attendees deletes it (and may notify them): asked first.
    @State private var showAttendeesConvertConfirm = false

    /// Which text field has focus, so the keyboard's sigil buttons know which one to append to
    /// (and stay hidden for the URL field, which must not get tags).
    private enum Field { case title, location, url, notes }
    @FocusState private var focusedField: Field?

    /// One stable "today" for the history stats, captured when the sheet is created.
    private let sheetToday = Date()

    init(item: AgendaItem, details: ItemDetails? = nil) {
        self.item = item
        self.details = details
        _form = State(initialValue: ItemEditForm(item: item))
        if case .event = item.kind { _kind = State(initialValue: .event) } else { _kind = State(initialValue: .reminder) }
    }

    var body: some View {
        NavigationStack {
            // A plain-style `List`, not `Form`: `Form` on iOS forces inset-grouped rounded
            // cards regardless of `.listStyle`, and the design has no rounded corners.
            List {
                Section {
                    TextField("Title", text: $form.title)
                        .focused($focusedField, equals: .title)
                    TagSuggestionRow(text: form.title) { form.title = TagAutocomplete.applying($0, to: form.title) }
                    if showsNoDate {
                        // An undated Apple reminder: its row date is a sentinel, never shown, and
                        // saving untouched keeps it undated (`ItemEditForm.showsNoDate`).
                        HStack {
                            Text(dateLabel)
                            Spacer()
                            Text(AgendaItem.noDateText).foregroundStyle(Colors.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        Button("Add Date") { form.addDueDate(on: Date()) }
                            .foregroundStyle(Colors.accent)
                            .accessibilityLabel("Add a due date")
                            .accessibilityHint("Sets the due date to today. You can change it afterwards.")
                    } else {
                        DatePicker(dateLabel, selection: $form.date,
                                   displayedComponents: form.allDay ? [.date] : [.date, .hourAndMinute])
                            .onChange(of: form.date) { oldValue, newValue in
                                // Moving the start moves the end with it, so the duration is kept.
                                form.endDate = EventSchedule.shiftedEnd(form.endDate, oldStart: oldValue, newStart: newValue)
                                // A repeat end never precedes the start's day.
                                form.repeatEnd = form.repeatEnd.clamped(toStartOn: newValue)
                            }
                        if isEvent {
                            DatePicker("Ends", selection: $form.endDate, in: form.date...,
                                       displayedComponents: form.allDay ? [.date] : [.date, .hourAndMinute])
                        }
                        Toggle("All day", isOn: $form.allDay)
                    }

                    if hasUnrepresentableRepeat {
                        // Never offered for editing and never part of a patch: the stored rule
                        // has a shape Stark's picker can't express.
                        LabeledContent("Repeat") {
                            Text("Custom, set in \(isEvent ? "Calendar" : "Reminders")")
                                .foregroundStyle(Colors.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Read only. Change this repeat in Apple's app.")
                    } else {
                        NavigationLink {
                            RepeatPickerView(recurrence: $form.recurrence)
                        } label: {
                            HStack {
                                Text("Repeat")
                                Spacer()
                                Text(recurrenceSummary).foregroundStyle(Colors.textSecondary)
                            }
                        }

                        if form.recurrence != nil {
                            NavigationLink {
                                RepeatEndPickerView(end: $form.repeatEnd, startDate: form.date)
                            } label: {
                                HStack {
                                    Text("Repeat End")
                                    Spacer()
                                    Text(form.repeatEnd.summary).foregroundStyle(Colors.textSecondary)
                                }
                            }
                        }
                    }

                    if isEvent {
                        TextField("Location", text: $form.location)
                            .focused($focusedField, equals: .location)
                        TagSuggestionRow(text: form.location) {
                            form.location = TagAutocomplete.applying($0, to: form.location)
                        }
                        TextField("URL", text: $form.url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .url)
                    }
                    if !isEvent {
                        // A segmented picker drops its label on iOS, so it is shown by the row.
                        LabeledContent("Priority") {
                            Picker("Priority", selection: $form.priority) {
                                ForEach(ReminderPriority.allCases, id: \.self) { Text($0.pickerLabel) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                    TextField("Notes", text: $form.notes, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($focusedField, equals: .notes)
                    TagSuggestionRow(text: form.notes) { form.notes = TagAutocomplete.applying($0, to: form.notes) }
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if item.isRecurring || hasUnrepresentableRepeat {
                            Text("Changes apply to every occurrence.")
                        }
                        if movesDetailsToNotes {
                            Text(isApple ? "The location will be added to the notes."
                                         : "Location and URL will be added to the notes.")
                        }
                        if details?.hasUnrepresentableRepeat == true {
                            Text(ItemDetails.unconvertibleReason)
                        }
                        if let source = item.appleSource {
                            Text("Saved in \(source.isReminder ? "Reminders" : "Calendar"): \(source.calendarTitle).")
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
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                }
                .disabled(isWorking)
                .listRowBackground(Colors.background)
            }
            // Flat list rows (not inset-grouped rounded cards) to keep hard edges.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Colors.background)
            .listRowSeparatorTint(Colors.separator)
            .onChange(of: form.recurrence) { _, newValue in
                // Repeat = Never resets the end.
                if newValue == nil { form.repeatEnd = .never }
            }
            .onChange(of: kind) { _, newKind in
                // An undated Apple reminder converted to an event needs a real start: today,
                // all day (never the sentinel date).
                if newKind == .event && isApple && form.showsNoDate { form.addDueDate(on: Date()) }
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
                VStack(spacing: 0) {
                    if let errorMessage {
                        SheetErrorBanner(text: errorMessage) { self.errorMessage = nil }
                    }
                    if let noticeMessage {
                        SheetErrorBanner(text: noticeMessage, isNotice: true) { self.noticeMessage = nil }
                    }
                    if canConvert {
                        KindSwitch(kind: kindSelection)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(Colors.background)
                    }
                }
            }
            .alert("Convert to Reminder?", isPresented: $showMarksConfirm) {
                Button("Convert", role: .destructive) { kind = .reminder }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(marksMessage)
            }
            .alert("Change the repeat?", isPresented: $showRuleChangeConfirm) {
                Button("Change", role: .destructive) { save(confirmRuleChange: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(ItemRouterError.ruleChangeConfirmation)
            }
            .alert("Convert this event?", isPresented: $showAttendeesConvertConfirm) {
                Button("Convert", role: .destructive) { save(confirmAttendees: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This event has invitees. Converting creates a reminder and deletes the event from Calendar, which may notify them.")
            }
            .navigationTitle(kind.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.background, for: .navigationBar)
            .toolbar {
                SquareToolbarButton(systemImage: "checkmark", label: "Save", placement: .confirmationAction,
                                    isProminent: true, isDisabled: form.trimmedTitle.isEmpty || isWorking) { save() }
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
        case .title: form.title = TagAutocomplete.appending(sigil, to: form.title)
        case .location: form.location = TagAutocomplete.appending(sigil, to: form.location)
        case .notes: form.notes = TagAutocomplete.appending(sigil, to: form.notes)
        case .url, nil: break
        }
    }

    // MARK: Derived state

    private var isApple: Bool { details != nil }

    /// An Apple reminder with no due date that the owner has not given one: "No date" instead of
    /// the sentinel date. Stark's own undated reminders keep the old picker (local unchanged).
    private var showsNoDate: Bool { isApple && !isEvent && form.showsNoDate }

    private var hasUnrepresentableRepeat: Bool { details?.hasUnrepresentableRepeat == true }

    /// Completion / attendance history for this item (recomputed from the store each render).
    /// None for Apple items: Apple keeps their completions, Stark does not (spec decision 1).
    private var history: CompletionHistory? {
        guard !isApple else { return nil }
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
    /// An Apple item also not when its repeat can't be represented (`ItemDetails.canConvert`).
    private var canConvert: Bool {
        if let details { return details.canConvert }
        switch item.kind {
        case .event: return true
        case .reminder(let reminder): return ItemConversion.isConvertible(reminder)
        }
    }

    /// Attended/skipped marks an event would lose by becoming a reminder. An Apple event's marks
    /// live in the sidecar and move to the new reminder with it, so none are lost.
    private var droppedMarks: Int {
        guard !isApple else { return 0 }
        if case .event(let event) = item.kind { return ItemConversion.droppedMarks(converting: event) }
        return 0
    }

    private var marksMessage: String {
        let marks = droppedMarks == 1 ? "1 attended/skipped mark" : "\(droppedMarks) attended/skipped marks"
        return "This event has \(marks). A reminder can't keep them, so they will be removed when you save."
    }

    /// Event -> reminder with a location or URL typed: those move into the notes on save. An
    /// Apple reminder keeps the URL as its own URL, so only the location moves.
    private var movesDetailsToNotes: Bool {
        isConverting && originalKind == .event
            && (FormFields.trimmedOrNil(form.location) != nil
                || (!isApple && FormFields.trimmedOrNil(form.url) != nil))
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

    private var recurrenceSummary: String {
        form.recurrence?.summary ?? "Never"
    }

    /// Events only: the typed URL when it is a well-formed http or https link, else nil.
    private var openableLink: URL? {
        guard isEvent,
              let link = URL(string: form.url.trimmingCharacters(in: .whitespacesAndNewlines)),
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

    /// Stark's own repeating reminders only; a recurring event's equivalent is "Remove This
    /// Occurrence" in `eventActions`. Apple Reminders can't skip one occurrence.
    private var showsSkip: Bool {
        guard !isApple else { return false }
        if case .reminder = item.kind { return item.isRecurring && !item.isCompleted }
        return false
    }

    /// Done / Skip / Undo / Remove This Occurrence, for events only.
    private var eventActions: EventOutcomeActions? {
        guard case .event = item.kind else { return nil }
        // An Apple repeat Stark can't represent is still a series (`ItemDeletePrompt.isSeries`).
        return EventOutcomeActions(outcome: item.outcome,
                                   isRecurring: ItemDeletePrompt.isSeries(isRecurring: item.isRecurring, details: details))
    }

    private var deleteMessage: String {
        ItemDeletePrompt.message(isRecurring: item.isRecurring,
                                 appleApp: item.appleSource.map { $0.isReminder ? "Reminders" : "Calendar" },
                                 details: details)
    }

    // MARK: Actions

    /// Runs one router call; dismisses on success, shows the message and stays open on failure.
    private func perform(_ operation: @escaping (ItemRouter) async throws -> Void) {
        guard let router, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await operation(router)
                dismiss()
            } catch let error as ItemRouterError where error.asksToConfirmRuleChange {
                showRuleChangeConfirm = true
            } catch {
                errorMessage = error.routerMessage
            }
        }
    }

    private func save(confirmRuleChange: Bool = false, confirmAttendees: Bool = false) {
        // Apple items diff against what an untouched form would write (spec call 5).
        let original = details?.formBaseline()
        let form = form
        switch (item.kind, kind) {
        case (.event(let event), .event):
            let edited = form.edited(event)
            perform { try await $0.update(event: edited, original: original, confirmRuleChange: confirmRuleChange) }
        case (.reminder(let reminder), .reminder):
            // The sheet has no reminder URL field: pass the stored one so it is kept.
            let edited = form.edited(reminder)
            perform { try await $0.update(reminder: edited, url: details?.reminderURL, original: original) }
        case (.event(let event), .reminder):
            if details?.convertAsksFirst == true && !confirmAttendees {
                showAttendeesConvertConfirm = true
                return
            }
            // Apply the form to the event, then convert (location/URL go into the notes, the end
            // and marks are dropped), then the reminder-only field. An Apple reminder keeps the
            // URL as its own URL instead.
            if isApple {
                let pair = ItemConversion.appleReminder(from: form.edited(event))
                var converted = pair.reminder
                converted.priority = form.priority.icalValue
                let url = pair.url
                perform { try await $0.convertEvent(id: event.id, to: converted, url: url) }
            } else {
                var converted = ItemConversion.reminder(from: form.edited(event))
                converted.priority = form.priority.icalValue
                perform { try await $0.convertEvent(id: event.id, to: converted) }
            }
        case (.reminder(let reminder), .event):
            // Priority is dropped; the form's Starts/Ends/All day and Location/URL apply (an
            // undated reminder lands all-day).
            var converted = ItemConversion.event(fromEdited: form.edited(reminder), originalDueDate: reminder.dueDate,
                                                 start: form.date, end: form.endDate, allDay: form.allDay)
            converted.location = FormFields.trimmedOrNil(form.location)
            // The sheet has no reminder URL field: an Apple reminder's stored URL carries over
            // unless one was typed for the event.
            converted.url = isApple
                ? ItemConversion.eventURL(typed: form.url, storedReminderURL: details?.reminderURL)
                : FormFields.trimmedOrNil(form.url)
            perform { try await $0.convertReminder(id: reminder.id, to: converted) }
        }
    }

    private func markDone() {
        guard case .reminder(let reminder) = item.kind else { return }
        let occurrence = item.occurrence
        perform { try await $0.complete(id: reminder.id, on: occurrence) }
    }

    /// The completed copy of a repeating Apple reminder is never reopened (the series can't move
    /// back): the sheet shows why and stays open. Anything else un-completes as before.
    private func markUndone() {
        guard case .reminder(let reminder) = item.kind else { return }
        if let notice = UncompleteNotice.text(for: item, snapshot: overlay.snapshot) {
            noticeMessage = notice
            return
        }
        perform { try await $0.uncomplete(id: reminder.id) }
    }

    private func markOutcome(_ outcome: EventOutcome?) {
        guard case .event(let event) = item.kind else { return }
        let occurrence = item.occurrence
        perform { try await $0.setEventOutcome(id: event.id, on: occurrence, outcome: outcome) }
    }

    private func skipOccurrence() {
        let occurrence = item.occurrence
        switch item.kind {
        case .event(let event): perform { try await $0.skipEvent(id: event.id, on: occurrence) }
        case .reminder(let reminder): perform { try await $0.skipReminder(id: reminder.id, on: occurrence) }
        }
    }

    private func delete() {
        switch item.kind {
        case .event(let event): perform { try await $0.deleteEvent(id: event.id) }
        case .reminder(let reminder): perform { try await $0.deleteReminder(id: reminder.id) }
        }
    }
}
