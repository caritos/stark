// ios/Sources/StarkKit/Planner/OccurrenceExpander.swift
import Foundation

public enum OccurrenceExpander {
    public static func occurrences(
        anchor: Date,
        rule: RecurrenceRule?,
        exceptionDates: [Date],
        in range: ClosedRange<Date>
    ) -> [Date] {
        let calendar = Calendar(identifier: .gregorian)

        guard let rule else {
            return range.contains(anchor) ? [anchor] : []
        }

        var results: [Date] = []
        var candidate = anchor
        var matchCount = 0

        // When there's no fixed occurrence count to track, `matches()` computes each
        // candidate's match purely from its calendar-arithmetic offset from `anchor`
        // (day/week/month/year difference), never from how many steps the walk has taken —
        // so it's safe to fast-forward straight to the display range instead of walking
        // day-by-day from a potentially years-old anchor. When `count` is set we must still
        // walk from `anchor`, since we need to know how many occurrences have already
        // happened to stop at the right one.
        if rule.count == nil, range.lowerBound > candidate {
            candidate = range.lowerBound
        }

        while candidate <= range.upperBound {
            if let until = rule.until, candidate > until { break }

            if matches(candidate, anchor: anchor, rule: rule, calendar: calendar) {
                matchCount += 1
                if let count = rule.count, matchCount > count { break }
                if candidate >= range.lowerBound,
                   !exceptionDates.contains(where: { calendar.isDate($0, inSameDayAs: candidate) }) {
                    results.append(candidate)
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { break }
            candidate = next
        }

        return results
    }

    public static func expand(event: Event, in range: ClosedRange<Date>) -> [Date] {
        occurrences(anchor: event.start, rule: event.recurrence, exceptionDates: event.exceptionDates, in: range)
    }

    public static func expand(reminder: Reminder, in range: ClosedRange<Date>) -> [Date] {
        guard let due = reminder.dueDate else { return [] }
        return occurrences(anchor: due, rule: reminder.recurrence, exceptionDates: reminder.exceptionDates, in: range)
    }

    private static func matches(_ date: Date, anchor: Date, rule: RecurrenceRule, calendar: Calendar) -> Bool {
        switch rule.frequency {
        case .daily:
            let days = calendar.dateComponents([.day], from: anchor, to: date).day ?? 0
            return days >= 0 && days % rule.interval == 0

        case .weekly:
            let weekday = Weekday(rawValue: calendar.component(.weekday, from: date) - 1)!
            let activeDays = rule.byDay ?? [Weekday(rawValue: calendar.component(.weekday, from: anchor) - 1)!]
            guard activeDays.contains(weekday) else { return false }
            let anchorWeekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
            let dateWeekStart = calendar.dateInterval(of: .weekOfYear, for: date)!.start
            let weeks = calendar.dateComponents([.weekOfYear], from: anchorWeekStart, to: dateWeekStart).weekOfYear ?? 0
            return weeks >= 0 && weeks % rule.interval == 0

        case .monthly:
            let anchorDay = rule.byMonthDay ?? calendar.component(.day, from: anchor)
            let expectedDay = min(anchorDay, calendar.range(of: .day, in: .month, for: date)!.count)
            guard calendar.component(.day, from: date) == expectedDay else { return false }
            let months = calendar.dateComponents([.month], from: anchor, to: date).month ?? 0
            return months >= 0 && months % rule.interval == 0

        case .yearly:
            let anchorParts = calendar.dateComponents([.month, .day], from: anchor)
            let expectedDay = min(anchorParts.day!, calendar.range(of: .day, in: .month, for: date)!.count)
            guard calendar.component(.month, from: date) == anchorParts.month,
                  calendar.component(.day, from: date) == expectedDay else { return false }
            let years = calendar.dateComponents([.year], from: anchor, to: date).year ?? 0
            return years >= 0 && years % rule.interval == 0
        }
    }
}
