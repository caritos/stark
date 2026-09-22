// ios/App/Stark/Stark/RepeatEndPickerView.swift
import SwiftUI
import StarkKit

/// Never / On Date / After N Times. Edits the screen's `RepeatEnd` state; the end is applied to the
/// rule on save (`RepeatEnd.applied(to:)`), so this view never touches the recurrence itself.
struct RepeatEndPickerView: View {
    @Binding var end: RepeatEnd
    /// The item's start: an end date is never offered before this day.
    let startDate: Date

    private static let defaultCount = 10

    private var startDay: Date {
        Calendar(identifier: .gregorian).startOfDay(for: startDate)
    }

    private var isNever: Bool {
        if case .never = end { return true }
        return false
    }

    private var isOnDate: Bool {
        if case .onDate = end { return true }
        return false
    }

    private var isAfterCount: Bool {
        if case .afterCount = end { return true }
        return false
    }

    /// The current end date; while another case is selected, the start's day.
    private var endDate: Binding<Date> {
        Binding(
            get: {
                if case .onDate(let date) = end { return max(date, startDay) }
                return startDay
            },
            set: { end = .onDate($0) }
        )
    }

    /// The current count; while another case is selected, the default.
    private var count: Binding<Int> {
        Binding(
            get: {
                if case .afterCount(let count) = end { return count }
                return Self.defaultCount
            },
            set: { end = .afterCount($0) }
        )
    }

    var body: some View {
        List {
            row("Never", isSelected: isNever) {
                end = .never
            }

            row("On Date", isSelected: isOnDate) {
                if !isOnDate { end = .onDate(startDay) }
            }
            if isOnDate {
                DatePicker("End Date", selection: endDate, in: startDay...,
                           displayedComponents: .date)
                    .foregroundStyle(Colors.text)
            }

            row("After N Times", isSelected: isAfterCount) {
                if !isAfterCount { end = .afterCount(Self.defaultCount) }
            }
            if isAfterCount {
                Stepper(RepeatEnd.afterCount(count.wrappedValue).summary,
                        value: count, in: 1...999)
                    .foregroundStyle(Colors.text)
            }
        }
        .navigationTitle("Repeat End")
    }

    private func row(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Colors.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Colors.accent)
                }
            }
        }
    }
}
