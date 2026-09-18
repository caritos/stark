// ios/App/Stark/Stark/CustomRepeatView.swift
import SwiftUI
import StarkKit

struct CustomRepeatView: View {
    @Binding var recurrence: RecurrenceRule?

    @State private var interval: Int
    @State private var unit: RecurrenceRule.Frequency
    @State private var byDay: Set<Weekday>
    @State private var byMonth: Set<Month>
    @State private var byMonthDay: [Int]?
    @State private var byPositionalDay: [PositionalDay]?
    @State private var endMode: EndMode
    @State private var untilDate: Date
    @State private var occurrenceCount: Int

    enum EndMode: String, CaseIterable, Identifiable {
        case never = "Never", onDate = "On Date", afterCount = "After"
        var id: String { rawValue }
    }

    init(recurrence: Binding<RecurrenceRule?>) {
        _recurrence = recurrence
        let existing = recurrence.wrappedValue
        _interval = State(initialValue: existing?.interval ?? 1)
        _unit = State(initialValue: existing?.frequency ?? .daily)
        _byDay = State(initialValue: Set(existing?.byDay ?? []))
        _byMonth = State(initialValue: Set(existing?.byMonth ?? []))
        _byMonthDay = State(initialValue: existing?.byMonthDay)
        _byPositionalDay = State(initialValue: existing?.byPositionalDay)
        _untilDate = State(initialValue: existing?.until ?? Date())
        _occurrenceCount = State(initialValue: existing?.count ?? 1)
        if existing?.until != nil {
            _endMode = State(initialValue: .onDate)
        } else if existing?.count != nil {
            _endMode = State(initialValue: .afterCount)
        } else {
            _endMode = State(initialValue: .never)
        }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Repeat").foregroundStyle(Colors.text)
                    Spacer()
                    Text(summary).foregroundStyle(Colors.textSecondary)
                }
            }

            Section {
                HStack {
                    Picker("Interval", selection: $interval) {
                        ForEach(1..<100, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()

                    Picker("Unit", selection: $unit) {
                        Text("day").tag(RecurrenceRule.Frequency.daily)
                        Text("week").tag(RecurrenceRule.Frequency.weekly)
                        Text("month").tag(RecurrenceRule.Frequency.monthly)
                        Text("year").tag(RecurrenceRule.Frequency.yearly)
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                }
                .frame(height: 216)
            }

            if unit == .weekly {
                Section("On Days") {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        Button {
                            toggle(day)
                        } label: {
                            HStack {
                                Text(dayName(day)).foregroundStyle(Colors.text)
                                Spacer()
                                if byDay.contains(day) {
                                    Image(systemName: "checkmark").foregroundStyle(Colors.accent)
                                }
                            }
                        }
                    }
                }
            }

            if unit == .monthly || unit == .yearly {
                if unit == .yearly {
                    Section("On Months") {
                        ForEach(Month.allCases, id: \.self) { month in
                            Button {
                                toggleMonth(month)
                            } label: {
                                HStack {
                                    Text(monthName(month)).foregroundStyle(Colors.text)
                                    Spacer()
                                    if byMonth.contains(month) {
                                        Image(systemName: "checkmark").foregroundStyle(Colors.accent)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        OnDaysPickerView(selectedDays: Binding(
                            get: { Set(byMonthDay ?? []) },
                            set: { newValue in
                                byMonthDay = newValue.isEmpty ? nil : Array(newValue).sorted()
                                if byMonthDay != nil { byPositionalDay = nil }
                            }
                        ))
                    } label: {
                        HStack {
                            Text("On Days").foregroundStyle(Colors.text)
                            Spacer()
                            Text(onDaysSummary).foregroundStyle(Colors.textSecondary)
                        }
                    }

                    NavigationLink {
                        OnWeekPickerView(entries: Binding(
                            get: { byPositionalDay ?? [] },
                            set: { newValue in
                                byPositionalDay = newValue.isEmpty ? nil : newValue
                                if byPositionalDay != nil { byMonthDay = nil }
                            }
                        ))
                    } label: {
                        HStack {
                            Text("On Week").foregroundStyle(Colors.text)
                            Spacer()
                            Text(onWeekSummary).foregroundStyle(Colors.textSecondary)
                        }
                    }
                }
            }

            Section("Ends") {
                Picker("Ends", selection: $endMode) {
                    ForEach(EndMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if endMode == .onDate {
                    DatePicker("Date", selection: $untilDate, displayedComponents: .date)
                } else if endMode == .afterCount {
                    Stepper("After \(occurrenceCount) times", value: $occurrenceCount, in: 1...999)
                }
            }
        }
        .navigationTitle("Custom")
        .onChange(of: interval) { _, _ in commit() }
        .onChange(of: unit) { _, _ in commit() }
        .onChange(of: byDay) { _, _ in commit() }
        .onChange(of: byMonth) { _, _ in commit() }
        .onChange(of: byMonthDay) { _, _ in commit() }
        .onChange(of: byPositionalDay) { _, _ in commit() }
        .onChange(of: endMode) { _, _ in commit() }
        .onChange(of: untilDate) { _, _ in commit() }
        .onChange(of: occurrenceCount) { _, _ in commit() }
        .onAppear { commit() }
    }

    private func toggle(_ day: Weekday) {
        if byDay.contains(day) { byDay.remove(day) } else { byDay.insert(day) }
    }

    private func toggleMonth(_ month: Month) {
        if byMonth.contains(month) { byMonth.remove(month) } else { byMonth.insert(month) }
    }

    private func buildRule() -> RecurrenceRule {
        RecurrenceRule(
            frequency: unit,
            interval: interval,
            byDay: unit == .weekly && !byDay.isEmpty ? Array(byDay).sorted { $0.rawValue < $1.rawValue } : nil,
            byMonthDay: (unit == .monthly || unit == .yearly) ? byMonthDay : nil,
            byPositionalDay: (unit == .monthly || unit == .yearly) ? byPositionalDay : nil,
            byMonth: unit == .yearly && !byMonth.isEmpty ? Array(byMonth).sorted { $0.rawValue < $1.rawValue } : nil,
            count: endMode == .afterCount ? occurrenceCount : nil,
            until: endMode == .onDate ? untilDate : nil
        )
    }

    private func commit() {
        recurrence = buildRule()
    }

    private var summary: String {
        buildRule().summary
    }

    private var onDaysSummary: String {
        guard let byMonthDay, !byMonthDay.isEmpty else { return "None" }
        return byMonthDay.map(String.init).joined(separator: ", ")
    }

    private var onWeekSummary: String {
        guard let byPositionalDay, !byPositionalDay.isEmpty else { return "None" }
        return "\(byPositionalDay.count) rule\(byPositionalDay.count == 1 ? "" : "s")"
    }

    private func dayName(_ day: Weekday) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][day.rawValue]
    }

    private func monthName(_ month: Month) -> String {
        ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"][month.rawValue - 1]
    }
}
