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

    /// The end to store for a timed event: nil unless strictly after the start, so an existing
    /// event that had no end is not given one just by opening and saving it.
    public static func storedEnd(_ end: Date, start: Date) -> Date? {
        end > start ? end : nil
    }
}
