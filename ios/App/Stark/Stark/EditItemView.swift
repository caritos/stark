// ios/App/Stark/Stark/EditItemView.swift
import SwiftUI
import StarkKit

/// Edit sheet for one writable Apple item, opened by `AppleItemEditor` once the stored item
/// (`details`) is loaded. Editable fields (title, date, all-day, end for timed events, repeat,
/// repeat end, notes, location and URL for events, priority for reminders) are committed only by
/// Save; the action buttons act immediately and dismiss. Reminders show Done / Delete (no Skip:
/// Apple Reminders can't skip one occurrence); events show Remove This Occurrence (a series) /
/// Open Link (for an http/https URL, does not dismiss) / Delete.
///
/// The Event / Reminder switch above the form converts the item (issue #116): the form switches
/// to the other kind's fields at once, but nothing is stored until Save, which replaces the item
/// (`ItemRouter.convertEvent` / `convertReminder`). While converting, the per-occurrence actions
/// (which belong to the old kind) are hidden.
///
/// Every write goes through `ItemRouter` (Apple only). The form is diffed against the stored
/// item's form baseline, so only the fields the owner changed are written (spec call 5); a repeat
/// Stark can't represent is shown read-only. A failed write shows its message in the sheet's
/// banner and the sheet stays open.
struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.itemRouter) private var router
    @Environment(AppleOverlayModel.self) private var overlay
    let item: AgendaItem
    /// The stored Apple item this sheet edits (`ItemRouter.details`). Its form baseline is the
    /// `original` every update diffs against (spec call 5).
    let details: ItemDetails

    /// The editable fields; the logic that turns them back into an item is StarkKit's.
    @State private var form: ItemEditForm
    @State private var showDeleteConfirm = false
    /// The kind the form describes; differs from the item's own kind while converting.
    @State private var kind: ItemKind
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

    init(item: AgendaItem, details: ItemDetails) {
        self.item = item
        self.details = details
        _form = State(initialValue: ItemEditForm(item: item))
        if case .event = item.kind { _kind = State(initialValue: .event) } else { _kind = State(initialValue: .reminder) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Title", text: $form.title)
                        .focused($focusedField, equals: .title)
                    TagSuggestionRow(text: form.title) { form.title = TagAutocomplete.applying($0, to: form.title) }
                }
                .listRowBackground(Colors.card)

                Section {
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
                        QuarterHourDatePicker(dateLabel, selection: $form.date,
                                              components: form.allDay ? .date : .dateAndTime)
                            .onChange(of: form.date) { oldValue, newValue in
                                // Moving the start moves the end with it, so the duration is kept.
                                form.endDate = EventSchedule.shiftedEnd(form.endDate, oldStart: oldValue, newStart: newValue)
                                // A repeat end never precedes the start's day.
                                form.repeatEnd = form.repeatEnd.clamped(toStartOn: newValue)
                            }
                        if isEvent {
                            QuarterHourDatePicker("Ends", selection: $form.endDate, minimumDate: form.date,
                                                  components: form.allDay ? .date : .dateAndTime)
                        }
                        Toggle("All day", isOn: $form.allDay)
                    }
                }
                .listRowBackground(Colors.card)

                Section {
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
                }
                .listRowBackground(Colors.card)

                Section {
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
                            Text("The location will be added to the notes.")
                        }
                        if details.hasUnrepresentableRepeat {
                            Text(ItemDetails.unconvertibleReason)
                        }
                        if let source = item.appleSource {
                            Text("Saved in \(source.isReminder ? "Reminders" : "Calendar"): \(source.calendarTitle).")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(Colors.textSecondary)
                }
                .listRowBackground(Colors.card)

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
                }
                .disabled(isWorking)
                .listRowBackground(Colors.card)

                Section {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Text("Delete \(isEvent ? "Event" : "Reminder")").frame(maxWidth: .infinity)
                    }
                }
                .disabled(isWorking)
                .listRowBackground(Colors.card)
            }
            .listStyle(.insetGrouped)
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
                if newKind == .event && form.showsNoDate { form.addDueDate(on: Date()) }
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
                        KindSwitch(kind: $kind)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(Colors.background)
                    }
                }
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

    /// A reminder with no due date that the owner has not given one: "No date" instead of the
    /// sentinel date.
    private var showsNoDate: Bool { !isEvent && form.showsNoDate }

    private var hasUnrepresentableRepeat: Bool { details.hasUnrepresentableRepeat }

    /// The form's kind (the converted one while converting), which decides the fields shown.
    private var isEvent: Bool { kind == .event }

    /// The item's own kind, before any conversion.
    private var originalKind: ItemKind {
        if case .event = item.kind { return .event }
        return .reminder
    }

    private var isConverting: Bool { kind != originalKind }

    /// An event, or an open reminder, unless its repeat can't be represented
    /// (`ItemDetails.canConvert`).
    private var canConvert: Bool { details.canConvert }

    /// Event -> reminder with a location typed: it moves into the notes on save. The reminder
    /// keeps the URL as its own URL, so only the location moves. (An event's attended/skipped
    /// marks live in the sidecar and move with it, so none are lost.)
    private var movesDetailsToNotes: Bool {
        isConverting && originalKind == .event && FormFields.trimmedOrNil(form.location) != nil
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
        // Diffed against what an untouched form would write (spec call 5).
        let original = details.formBaseline()
        let form = form
        switch (item.kind, kind) {
        case (.event(let event), .event):
            let edited = form.edited(event)
            perform { try await $0.update(event: edited, original: original, confirmRuleChange: confirmRuleChange) }
        case (.reminder(let reminder), .reminder):
            // The sheet has no reminder URL field: pass the stored one so it is kept.
            let edited = form.edited(reminder)
            perform { try await $0.update(reminder: edited, url: details.reminderURL, original: original) }
        case (.event(let event), .reminder):
            if details.convertAsksFirst && !confirmAttendees {
                showAttendeesConvertConfirm = true
                return
            }
            // Apply the form to the event, then convert (the location goes into the notes, the
            // end is dropped, the URL stays the reminder's own URL), then the reminder-only field.
            let pair = ItemConversion.appleReminder(from: form.edited(event))
            var converted = pair.reminder
            converted.priority = form.priority.icalValue
            let url = pair.url
            perform { try await $0.convertEvent(id: event.id, to: converted, url: url) }
        case (.reminder(let reminder), .event):
            // Priority is dropped; the form's Starts/Ends/All day and Location/URL apply (an
            // undated reminder lands all-day).
            var converted = ItemConversion.event(fromEdited: form.edited(reminder), originalDueDate: reminder.dueDate,
                                                 start: form.date, end: form.endDate, allDay: form.allDay)
            converted.location = FormFields.trimmedOrNil(form.location)
            // The sheet has no reminder URL field: the reminder's stored URL carries over unless
            // one was typed for the event.
            converted.url = ItemConversion.eventURL(typed: form.url, storedReminderURL: details.reminderURL)
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

    /// "Remove This Occurrence" (events only: Apple Reminders can't skip one occurrence).
    private func skipOccurrence() {
        guard case .event(let event) = item.kind else { return }
        let occurrence = item.occurrence
        perform { try await $0.skipEvent(id: event.id, on: occurrence) }
    }

    private func delete() {
        switch item.kind {
        case .event(let event): perform { try await $0.deleteEvent(id: event.id) }
        case .reminder(let reminder): perform { try await $0.deleteReminder(id: reminder.id) }
        }
    }
}
