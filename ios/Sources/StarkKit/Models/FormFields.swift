// ios/Sources/StarkKit/Models/FormFields.swift
import Foundation

/// Small pure helpers the add/edit screens share, kept out of the views so they are testable.
public enum FormFields {
    /// The text with outer whitespace/newlines trimmed, or nil when nothing is left.
    public static func trimmedOrNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// An all-day item is stored at the start of its day; a timed one is stored as picked.
    public static func normalizedStart(_ date: Date, allDay: Bool) -> Date {
        allDay ? Calendar(identifier: .gregorian).startOfDay(for: date) : date
    }

    /// True when the date is exactly local midnight — the model's "date only" marker for reminders.
    public static func isAllDay(_ date: Date) -> Bool {
        Calendar(identifier: .gregorian).startOfDay(for: date) == date
    }

    /// The All-day toggle's initial value when a reminder is opened for editing: on for a
    /// date-only due date; an undated reminder is not all-day.
    public static func isAllDay(_ reminder: Reminder) -> Bool {
        reminder.dueDate.map(isAllDay) ?? false
    }
}
