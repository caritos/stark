// ios/App/Stark/Stark/AddItemView.swift
import SwiftUI
import StarkKit

struct AddItemView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: Kind = .event
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

    enum Kind: String, CaseIterable { case event = "Event", reminder = "Reminder" }

    /// Which text field has focus, so the keyboard's sigil buttons know which one to append to
    /// (and stay hidden for the URL field, which must not get tags).
    private enum Field { case title, notes, url }
    @FocusState private var focusedField: Field?

    init() {
        let now = Date()
        _date = State(initialValue: now)
        _endDate = State(initialValue: now.addingTimeInterval(EventSchedule.defaultDuration))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                    .focused($focusedField, equals: .title)
                TagSuggestionRow(text: title) { title = TagAutocomplete.applying($0, to: title) }
                DatePicker(kind == .event ? "Starts" : "Due", selection: $date,
                           displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    .onChange(of: date) { oldValue, newValue in
                        // Moving the start moves the end with it, so the duration is kept.
                        endDate = EventSchedule.shiftedEnd(endDate, oldStart: oldValue, newStart: newValue)
                        // A repeat end never precedes the start's day.
                        repeatEnd = repeatEnd.clamped(toStartOn: newValue)
                    }
                if kind == .event {
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
            .onChange(of: recurrence) { _, newValue in
                // Repeat = Never resets the end.
                if newValue == nil { repeatEnd = .never }
            }
            .task {
                // Full-history corpus for tag suggestions (`+`/`@`/`%`/`~`); non-blocking --
                // suggestions simply improve as more months finish loading, same as Search.
                await store.loadAllMonths()
            }
            .sigilKeyboardBar(isVisible: focusedField == .title || focusedField == .notes,
                              onTap: insertSigil)
            // Big, high-contrast two-way switch pinned above the form (issue #109): the stock
            // segmented control was small, grey-on-grey and sat inside the form's rounded card.
            .safeAreaInset(edge: .top, spacing: 0) {
                KindSwitch(kind: $kind)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Colors.background)
            }
            .navigationTitle("Add \(kind.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SquareToolbarButton(systemImage: "plus", label: "Add", placement: .confirmationAction,
                                    isProminent: true,
                                    isDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty) { add() }
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

    private func add() {
        let start = FormFields.normalizedStart(date, allDay: allDay)
        switch kind {
        case .event:
            store.addEvent(Event(
                title: title,
                notes: FormFields.trimmedOrNil(notes),
                start: start,
                end: EventSchedule.storedEnd(endDate, start: date, allDay: allDay),
                isAllDay: allDay,
                // No Location field on Add -- keeps the add form quick; it can still be set
                // afterward via Edit.
                recurrence: repeatEnd.applied(to: recurrence),
                url: FormFields.trimmedOrNil(url)
            ))
        case .reminder:
            store.addReminder(Reminder(
                title: title,
                notes: FormFields.trimmedOrNil(notes),
                dueDate: start,
                priority: priority.icalValue,
                recurrence: repeatEnd.applied(to: recurrence)
            ))
        }
        dismiss()
    }
}

/// Event / Reminder switch: two flat 48 pt squares side by side, the chosen one filled with the
/// accent, the other outlined. Square and flat like the rest of the app (no rounded segments).
private struct KindSwitch: View {
    @Binding var kind: AddItemView.Kind

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AddItemView.Kind.allCases, id: \.self) { option in
                let selected = option == kind
                Button {
                    kind = option
                } label: {
                    Text(option.rawValue)
                        .font(Fonts.mono(15, weight: .semibold))
                        .foregroundStyle(selected ? Colors.background : Colors.text)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(selected ? Colors.accent : Color.clear)
                        .overlay(Rectangle().strokeBorder(selected ? Colors.accent : Colors.checkboxBorder, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
