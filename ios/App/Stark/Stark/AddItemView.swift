// ios/App/Stark/Stark/AddItemView.swift
import SwiftUI
import StarkKit

struct AddItemView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: Kind = .event
    @State private var title = ""
    @State private var date = Date()
    @State private var recurrence: RecurrenceRule?

    enum Kind: String, CaseIterable { case event = "Event", reminder = "Reminder" }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                TextField("Title", text: $title)
                DatePicker(kind == .event ? "Start" : "Due", selection: $date)

                NavigationLink {
                    RepeatPickerView(recurrence: $recurrence)
                } label: {
                    HStack {
                        Text("Repeat")
                        Spacer()
                        Text(recurrenceSummary).foregroundStyle(Colors.textSecondary)
                    }
                }
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
        switch kind {
        case .event:
            store.addEvent(Event(title: title, start: date, recurrence: recurrence))
        case .reminder:
            store.addReminder(Reminder(title: title, dueDate: date, recurrence: recurrence))
        }
        dismiss()
    }
}
