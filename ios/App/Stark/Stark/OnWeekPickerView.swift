// ios/App/Stark/Stark/OnWeekPickerView.swift
import SwiftUI
import StarkKit

struct OnWeekPickerView: View {
    @Binding var entries: [PositionalDay]

    private var hasGenericEntry: Bool {
        entries.contains { if case .weekday = $0.dayType { return false } else { return true } }
    }

    private func isAnyDay(_ dayType: DayTypeOrWeekday) -> Bool {
        if case .anyDay = dayType { return true }
        return false
    }

    var body: some View {
        Form {
            ForEach(entries.indices, id: \.self) { index in
                Section {
                    Picker("Position", selection: Binding(
                        get: { entries[index].position },
                        set: { entries[index].position = $0 }
                    )) {
                        Text("First").tag(Position.first)
                        Text("Second").tag(Position.second)
                        Text("Third").tag(Position.third)
                        Text("Fourth").tag(Position.fourth)
                        Text("Last").tag(Position.last)
                    }
                    // "Day" only ever pairs with "Last" - any other position would encode as a
                    // plain BYMONTHDAY indistinguishable from a non-positional day-of-month rule
                    // on decode (see RRuleCodec's encoding notes), and is redundant with "On Days"
                    // anyway ("the 2nd day of the month" is just byMonthDay: [2]).
                    .disabled(isAnyDay(entries[index].dayType))

                    Picker("Day", selection: Binding(
                        get: { entries[index].dayType },
                        set: { newValue in
                            entries[index].dayType = newValue
                            switch newValue {
                            case .anyDay:
                                // The only unambiguous pairing - force position to .last.
                                entries[index].position = .last
                                entries = [entries[index]]
                            case .weekdayOnly, .weekendDay:
                                // Also must be the sole entry (see RRULE encoding constraint in the spec).
                                entries = [entries[index]]
                            case .weekday:
                                break
                            }
                        }
                    )) {
                        Text("Sunday").tag(DayTypeOrWeekday.weekday(.sunday))
                        Text("Monday").tag(DayTypeOrWeekday.weekday(.monday))
                        Text("Tuesday").tag(DayTypeOrWeekday.weekday(.tuesday))
                        Text("Wednesday").tag(DayTypeOrWeekday.weekday(.wednesday))
                        Text("Thursday").tag(DayTypeOrWeekday.weekday(.thursday))
                        Text("Friday").tag(DayTypeOrWeekday.weekday(.friday))
                        Text("Saturday").tag(DayTypeOrWeekday.weekday(.saturday))
                        Text("Day").tag(DayTypeOrWeekday.anyDay)
                        Text("Weekday").tag(DayTypeOrWeekday.weekdayOnly)
                        Text("Weekend Day").tag(DayTypeOrWeekday.weekendDay)
                    }

                    Button("Remove", role: .destructive) {
                        entries.remove(at: index)
                    }
                }
            }

            if !hasGenericEntry {
                Button("Add Rule") {
                    entries.append(PositionalDay(position: .first, dayType: .weekday(.sunday)))
                }
            }
        }
        .navigationTitle("On Week")
    }
}
