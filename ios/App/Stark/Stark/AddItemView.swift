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
    @State private var location = ""
    @State private var url = ""
    @State private var priority: ReminderPriority = .none

    enum Kind: String, CaseIterable { case event = "Event", reminder = "Reminder" }

    init() {
        let now = Date()
        _date = State(initialValue: now)
        _endDate = State(initialValue: now.addingTimeInterval(EventSchedule.defaultDuration))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                TextField("Title", text: $title)
                DatePicker(kind == .event ? "Starts" : "Due", selection: $date,
                           displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    .onChange(of: date) { oldValue, newValue in
                        // Moving the start moves the end with it, so the duration is kept.
                        endDate = EventSchedule.shiftedEnd(endDate, oldStart: oldValue, newStart: newValue)
                        // A repeat end never precedes the start's day.
                        repeatEnd = repeatEnd.clamped(toStartOn: newValue)
                    }
                if kind == .event && !allDay {
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

                if kind == .event {
                    TextField("Location", text: $location)
                    TextField("URL", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
            }
            .onChange(of: recurrence) { _, newValue in
                // Repeat = Never resets the end.
                if newValue == nil { repeatEnd = .never }
            }
            .navigationTitle("Add \(kind.rawValue)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
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
                end: allDay ? nil : EventSchedule.storedEnd(endDate, start: date),
                isAllDay: allDay,
                location: FormFields.trimmedOrNil(location),
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
