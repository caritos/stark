// ios/Sources/StarkKit/Models/RepeatEnd.swift
import Foundation

extension RecurrenceRule {
    /// The rule with its end (`count` and `until`) cleared. The add/edit screens keep the end
    /// separately (`RepeatEnd`) because the repeat picker replaces the whole rule.
    public var withoutEnd: RecurrenceRule {
        var copy = self
        copy.count = nil
        copy.until = nil
        return copy
    }
}

/// When a recurring item stops repeating: never, after a date, or after a number of occurrences.
/// Maps onto `RecurrenceRule.until` (date-only, inclusive) and `RecurrenceRule.count`.
public enum RepeatEnd: Equatable, Sendable {
    case never
    case onDate(Date)
    case afterCount(Int)

    /// Reads a rule's end. A count below 1 is nonsense and reads as `.never`; if a rule somehow
    /// has both, the date wins (an RRULE may not carry both).
    public init(rule: RecurrenceRule?) {
        if let until = rule?.until {
            self = .onDate(until)
        } else if let count = rule?.count, count >= 1 {
            self = .afterCount(count)
        } else {
            self = .never
        }
    }

    /// `rule` with this end applied, replacing any earlier end; nil stays nil. An end date is
    /// stored at the start of its day (`UNTIL` is date-only) and a count is at least 1. Applying an
    /// item's own end to its `withoutEnd` rule gives back the original rule exactly.
    public func applied(to rule: RecurrenceRule?) -> RecurrenceRule? {
        guard var result = rule?.withoutEnd else { return nil }
        switch self {
        case .never:
            break
        case .onDate(let date):
            result.until = Calendar(identifier: .gregorian).startOfDay(for: date)
        case .afterCount(let count):
            result.count = max(count, 1)
        }
        return result
    }

    /// An end date earlier than the day the item starts moves up to that day; every other end is
    /// returned unchanged.
    public func clamped(toStartOn start: Date) -> RepeatEnd {
        guard case .onDate(let date) = self else { return self }
        let calendar = Calendar(identifier: .gregorian)
        let startDay = calendar.startOfDay(for: start)
        return calendar.startOfDay(for: date) < startDay ? .onDate(startDay) : self
    }

    /// The Repeat End row's value: "Never", "Dec 31, 2026", "1 time", "10 times".
    public var summary: String {
        switch self {
        case .never:
            return "Never"
        case .onDate(let date):
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        case .afterCount(let count):
            return count == 1 ? "1 time" : "\(count) times"
        }
    }
}
