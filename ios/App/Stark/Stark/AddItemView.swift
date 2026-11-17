// ios/App/Stark/Stark/AddItemView.swift
import SwiftUI
import StarkKit

/// Adds an event or a reminder. New items always go to Apple (spec: no local option) through the
/// router, into the calendar or list picked here (writable ones only; the default destination is
/// preselected). Without access or a writable destination Save is off and a message points to
/// Settings. A failed save shows the router's message and keeps the sheet open.
struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.itemRouter) private var router
    @Environment(DefaultDestinationModel.self) private var destinations
    @Environment(AppleOverlayModel.self) private var overlay
    @Environment(NoticeCenter.self) private var notices
    /// Closes Add and opens Stark's Settings (access, default calendar and list).
    private let onOpenSettings: () -> Void

    @State private var kind: ItemKind = .event
    @State private var title = ""
    @State private var date: Date
    @State private var endDate: Date
    @State private var allDay = false
    /// Kept without its end (`withoutEnd`); the end is `repeatEnd`, applied on add, because the
    /// repeat presets replace the whole rule.
    @State private var recurrence: RecurrenceRule?
    @State private var repeatEnd: RepeatEnd = .never
    @State private var notes = ""
    @State private var url = ""
    @State private var priority: ReminderPriority = .none
    /// The picked calendar / list; nil means "the default destination" (`AddDestination`).
    @State private var pickedCalendarID: String?
    @State private var pickedListID: String?
    @State private var errorMessage: String?
    @State private var isSaving = false

    /// Which text field has focus, so the keyboard's sigil buttons know which one to append to
    /// (and stay hidden for the URL field, which must not get tags).
    private enum Field { case title, notes, url }
    @FocusState private var focusedField: Field?

    init(onOpenSettings: @escaping () -> Void = {}) {
        self.onOpenSettings = onOpenSettings
        // A new item starts at the next quarter hour, the only minutes the pickers offer.
        let start = QuarterHour.nextAfter(Date())
        _date = State(initialValue: start)
        _endDate = State(initialValue: start.addingTimeInterval(EventSchedule.defaultDuration))
    }

    var body: some View {
        NavigationStack {
            Form {
                destinationSection
                Section {
                TextField("Title", text: $title)
                    .focused($focusedField, equals: .title)
                TagSuggestionRow(text: title) { title = TagAutocomplete.applying($0, to: title) }
                }
                Section {
                QuarterHourDatePicker(kind == .event ? "Starts" : "Due", selection: $date,
                                      components: allDay ? .date : .dateAndTime)
                    .onChange(of: date) { oldValue, newValue in
                        // Moving the start moves the end with it, so the duration is kept.
                        endDate = EventSchedule.shiftedEnd(endDate, oldStart: oldValue, newStart: newValue)
                        // A repeat end never precedes the start's day.
                        repeatEnd = repeatEnd.clamped(toStartOn: newValue)
                    }
                if kind == .event {
                    QuarterHourDatePicker("Ends", selection: $endDate, minimumDate: date,
                                          components: allDay ? .date : .dateAndTime)
                }
                Toggle("All day", isOn: $allDay)
                }

                Section {
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
                }

                Section {
                if kind == .event {
                    TextField("URL", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .url)
                }
                if kind == .reminder {
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
                }
            }
            .scrollContentBackground(.hidden)
            .background(Colors.background)
            .onChange(of: recurrence) { _, newValue in
                // Repeat = Never resets the end.
                if newValue == nil { repeatEnd = .never }
            }
            .sigilKeyboardBar(isVisible: focusedField == .title || focusedField == .notes,
                              onTap: insertSigil)
            // Big, high-contrast two-way switch pinned above the form (issue #109): the stock
            // segmented control was small, grey-on-grey and sat inside the form's rounded card.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if let errorMessage {
                        SheetErrorBanner(text: errorMessage) { self.errorMessage = nil }
                    }
                    KindSwitch(kind: $kind)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Colors.background)
                }
            }
            .navigationTitle("Add \(kind.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SquareToolbarButton(systemImage: "plus", label: "Add", placement: .confirmationAction,
                                    isProminent: true,
                                    isDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty
                                        || selectedDestination == nil || isSaving) { add() }
                SquareToolbarButton(systemImage: "xmark", label: "Cancel", placement: .cancellationAction) { dismiss() }
            }
        }
        .tint(Colors.accent)
    }

    private func insertSigil(_ sigil: Character) {
        switch focusedField {
        case .title: title = TagAutocomplete.appending(sigil, to: title)
        case .notes: notes = TagAutocomplete.appending(sigil, to: notes)
        case .url, nil: break
        }
    }

    private var recurrenceSummary: String {
        guard let recurrence else { return "Never" }
        return recurrence.summary
    }

    // MARK: Destination

    private var isEvent: Bool { kind == .event }

    private var choices: [AppleCalendarInfo] {
        isEvent ? destinations.calendarChoices : destinations.listChoices
    }

    private var destinationState: AddDestination.State {
        AddDestination.state(hasAccess: overlay.access == .granted, choices: choices,
                             defaultID: isEvent ? destinations.calendarID : destinations.listID)
    }

    /// The calendar or list the item will go to: the picked one while it is still offered, else
    /// the default; nil when there is none (Save is off).
    private var selectedDestination: String? {
        let picked = isEvent ? pickedCalendarID : pickedListID
        if let picked, choices.contains(where: { $0.id == picked }) { return picked }
        guard case .ready(let selected) = destinationState else { return nil }
        return selected
    }

    private var destinationBinding: Binding<String?> {
        Binding(
            get: { selectedDestination },
            set: { id in
                if isEvent { pickedCalendarID = id } else { pickedListID = id }
            }
        )
    }

    @ViewBuilder
    private var destinationSection: some View {
        if let message = AddDestination.message(destinationState, isEvent: isEvent) {
            Section {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Colors.text)
                Button("Open Settings") { onOpenSettings() }
                    .foregroundStyle(Colors.accent)
                    .accessibilityHint("Closes Add and opens Stark's Settings.")
            }
            }
        }
        // No picker: the Event / Reminder switch above decides the kind, and the calendar or list
        // is the default chosen in Settings.
    }

    private func add() {
        guard let router, let destination = selectedDestination, !isSaving else { return }
        let start = FormFields.normalizedStart(date, allDay: allDay)
        let event = Event(
            title: title,
            notes: FormFields.trimmedOrNil(notes),
            start: start,
            end: EventSchedule.storedEnd(endDate, start: date, allDay: allDay),
            isAllDay: allDay,
            // No Location field on Add -- keeps the add form quick; it can still be set
            // afterward via Edit.
            recurrence: repeatEnd.applied(to: recurrence),
            url: FormFields.trimmedOrNil(url)
        )
        let reminder = Reminder(
            title: title,
            notes: FormFields.trimmedOrNil(notes),
            dueDate: start,
            priority: priority.icalValue,
            recurrence: repeatEnd.applied(to: recurrence)
        )
        let isEvent = isEvent
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                // A picked calendar that is hidden in the overlay is shown again first, so the new
                // item never vanishes from view (decision 11, as for the default destination).
                if !overlay.selection.isShown(destination) { overlay.setShown(destination, true) }
                if isEvent {
                    try await router.add(event: event, calendarID: destination)
                } else {
                    try await router.add(reminder: reminder, listID: destination)
                }
                // Posted on the main screen's strip (the sheet's presenter), which shows once the
                // sheet closes. Plain "Added" when the destination's info is not in the list.
                notices.show(DestinationLabel.addedNotice(calendar: choices.first { $0.id == destination }))
                dismiss()
            } catch {
                errorMessage = error.routerMessage
            }
        }
    }
}
