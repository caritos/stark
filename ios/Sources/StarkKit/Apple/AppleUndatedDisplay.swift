// ios/Sources/StarkKit/Apple/AppleUndatedDisplay.swift
import Foundation

/// Undated Apple reminders (spec Decision 3) carry a sentinel occurrence (`.distantPast` in
/// Search, `.distantFuture` in the planner) so they sort and key stably; that date must never be
/// shown ("12/31/01", "Dec 31, 1"). Stark's own undated reminders keep their old text (local
/// behaviour unchanged).
extension AgendaItem {
    public static let noDateText = "No date"

    /// An Apple reminder row with no due date.
    public var isUndatedApple: Bool {
        guard appleSource != nil, case .reminder(let reminder) = kind else { return false }
        return reminder.dueDate == nil
    }

    /// The row's date line: "No date" for an undated Apple reminder, else `format(displayDate)`.
    public func dateText(_ format: (Date) -> String) -> String {
        isUndatedApple ? Self.noDateText : format(displayDate)
    }
}

extension ItemEditForm {
    /// True while the form edits a reminder that has no due date and the owner has not given it
    /// one: the sheet shows "No date" (and an Add Date button) instead of the sentinel date.
    public var showsNoDate: Bool {
        startedUndated && date == initialDate && allDay == initialAllDay
    }

    /// Gives an undated reminder a date-only due date on `day`'s calendar day. `edited` then
    /// writes it (the date differs from the form's initial one).
    public mutating func addDueDate(on day: Date, calendar: Calendar = Calendar(identifier: .gregorian)) {
        allDay = true
        date = calendar.startOfDay(for: day)
    }
}
