// ios/Sources/StarkKit/Models/EventSchedule.swift
import Foundation

/// Pure rules for the add/edit screens' Starts/Ends pickers, kept out of the views so they are
/// testable.
public enum EventSchedule {
    /// A new timed event is one hour long (the same default as Fantastical).
    public static let defaultDuration: TimeInterval = 3600

    /// The end after the start moved from `oldStart` to `newStart`: the duration is kept.
    public static func shiftedEnd(_ end: Date, oldStart: Date, newStart: Date) -> Date {
        end.addingTimeInterval(newStart.timeIntervalSince(oldStart))
    }

    /// The Ends picker's initial value when an event is opened for editing: its end, or Starts
    /// when it has none. For an all-day event the end is its (inclusive) last day.
    public static func formEnd(for event: Event) -> Date {
        event.end ?? event.start
    }

    /// The end to store: nil unless strictly after the start, so an existing event that had no
    /// end is not given one just by opening and saving it. An all-day end is the start of its
    /// last day, and counts only when that day is after the start's day.
    public static func storedEnd(_ end: Date, start: Date, allDay: Bool = false) -> Date? {
        guard allDay else { return end > start ? end : nil }
        let calendar = Calendar(identifier: .gregorian)
        let lastDay = calendar.startOfDay(for: end)
        return lastDay > calendar.startOfDay(for: start) ? lastDay : nil
    }
}
