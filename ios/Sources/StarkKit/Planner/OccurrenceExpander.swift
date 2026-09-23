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
        //
        // The fast-forward target must carry the ANCHOR's time-of-day (on the day `lowerBound`
        // falls on), never `lowerBound`'s own: every later candidate is derived from this one by
        // whole-day steps, so a foreign time-of-day would stamp every returned occurrence with it,
        // and `matches()`'s day/month/year differences (computed from `anchor` to the candidate)
        // would truncate differently and shift interval > 1 alignment. Landing at or before
        // `lowerBound` is fine: the `candidate >= range.lowerBound` check below trims anything
        // that precedes the range.
        if rule.count == nil, range.lowerBound > candidate,
           let fastForwarded = sameTimeOfDay(as: anchor, onDayOf: range.lowerBound, calendar: calendar),
           fastForwarded > candidate {
            candidate = fastForwarded
        }

        while candidate <= range.upperBound {
            // Compare `until` at calendar-day granularity, not exact datetime. `until` is always
            // encoded date-only (decodes to local midnight), but a real anchor almost always
            // carries a non-midnight time-of-day - a candidate on the `until` date itself, at any
            // time after midnight, would otherwise be `>` the midnight `until` value and get cut
            // off one day early, silently dropping the very last occurrence the user configured
            // ("ends on this date"). Fixed here (not by how `until` is encoded) so a `until` value
            // arriving from anywhere else (e.g. an imported .ics) behaves the same way.
            if let until = rule.until, calendar.startOfDay(for: candidate) > calendar.startOfDay(for: until) { break }

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

    /// The moment on `day`'s calendar day that has `reference`'s wall-clock time-of-day.
    private static func sameTimeOfDay(as reference: Date, onDayOf day: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: reference)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        components.nanosecond = time.nanosecond
        return calendar.date(from: components)
    }

    public static func expand(event: Event, in range: ClosedRange<Date>) -> [Date] {
        occurrences(anchor: event.start, rule: event.recurrence, exceptionDates: event.exceptionDates, in: range)
    }

    /// A `nil` `dueDate` returns no occurrences ever, by design: undated reminders are
    /// deliberately not a supported feature (the agenda only lists dated items — see
    /// "Add/edit fields" in the root CLAUDE.md), and `AddItemView` never constructs one. This is
    /// not reachable in practice today, but a future code path that did construct an undated
    /// reminder would store it permanently invisible rather than erroring, which is worth knowing
    /// if this ever needs debugging.
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
            // `calendar` is always a bare `Calendar(identifier: .gregorian)` with no `.locale`
            // set (see `occurrences` above), which fixes `firstWeekday` at 1 (Sunday) regardless
            // of device region -- confirmed empirically, not locale-derived (a bare Calendar's
            // locale is a "fixed empty" one, distinct from `Calendar.current`). This is
            // deliberate, not a latent bug: the whole app is Sunday-first everywhere else
            // (MonthGrid, the mini-grid headers), so `every:N>1` week-interval parity below is
            // already consistent with that, and must never be made locale-adaptive.
            let weekday = Weekday(rawValue: calendar.component(.weekday, from: date) - 1)!
            let activeDays = rule.byDay ?? [Weekday(rawValue: calendar.component(.weekday, from: anchor) - 1)!]
            guard activeDays.contains(weekday) else { return false }
            let anchorWeekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
            let dateWeekStart = calendar.dateInterval(of: .weekOfYear, for: date)!.start
            let weeks = calendar.dateComponents([.weekOfYear], from: anchorWeekStart, to: dateWeekStart).weekOfYear ?? 0
            return weeks >= 0 && weeks % rule.interval == 0

        case .monthly:
            let year = calendar.component(.year, from: date)
            let month0 = calendar.component(.month, from: date) - 1
            let daysInMonth = calendar.range(of: .day, in: .month, for: date)!.count
            let candidateDay = calendar.component(.day, from: date)
            guard dayMatches(candidateDay: candidateDay, daysInMonth: daysInMonth, year: year, month0: month0, rule: rule, anchor: anchor, calendar: calendar) else { return false }
            let months = calendar.dateComponents([.month], from: anchor, to: date).month ?? 0
            return months >= 0 && months % rule.interval == 0

        case .yearly:
            let candidateMonth = calendar.component(.month, from: date)
            let monthMatches: Bool
            if let byMonth = rule.byMonth, !byMonth.isEmpty {
                monthMatches = byMonth.contains { $0.rawValue == candidateMonth }
            } else {
                monthMatches = candidateMonth == calendar.component(.month, from: anchor)
            }
            guard monthMatches else { return false }

            let year = calendar.component(.year, from: date)
            let month0 = candidateMonth - 1
            let daysInMonth = calendar.range(of: .day, in: .month, for: date)!.count
            let candidateDay = calendar.component(.day, from: date)
            guard dayMatches(candidateDay: candidateDay, daysInMonth: daysInMonth, year: year, month0: month0, rule: rule, anchor: anchor, calendar: calendar) else { return false }

            let years = calendar.dateComponents([.year], from: anchor, to: date).year ?? 0
            return years >= 0 && years % rule.interval == 0
        }
    }

    private static func matchesDayType(_ dayType: DayTypeOrWeekday, weekday: Weekday) -> Bool {
        switch dayType {
        case .weekday(let w): return weekday == w
        case .anyDay: return true
        case .weekdayOnly: return weekday != .sunday && weekday != .saturday
        case .weekendDay: return weekday == .sunday || weekday == .saturday
        }
    }

    private static func resolvePositionalDay(_ positional: PositionalDay, year: Int, month0: Int) -> Int? {
        let daysInMonth = DateMath.daysInMonth(year: year, month0: month0)
        var matchingDays: [Int] = []
        for day in 1...daysInMonth {
            let weekdayIndex = DateMath.weekday(year: year, month0: month0, day: day)
            let weekday = Weekday(rawValue: weekdayIndex)!
            if matchesDayType(positional.dayType, weekday: weekday) {
                matchingDays.append(day)
            }
        }
        switch positional.position {
        case .first: return matchingDays.first
        case .second: return matchingDays.count >= 2 ? matchingDays[1] : nil
        case .third: return matchingDays.count >= 3 ? matchingDays[2] : nil
        case .fourth: return matchingDays.count >= 4 ? matchingDays[3] : nil
        case .last: return matchingDays.last
        }
    }

    private static func dayMatches(candidateDay: Int, daysInMonth: Int, year: Int, month0: Int, rule: RecurrenceRule, anchor: Date, calendar: Calendar) -> Bool {
        if let positionalDays = rule.byPositionalDay, !positionalDays.isEmpty {
            return positionalDays.contains { resolvePositionalDay($0, year: year, month0: month0) == candidateDay }
        }
        if let byMonthDay = rule.byMonthDay, !byMonthDay.isEmpty {
            return byMonthDay.contains { min($0, daysInMonth) == candidateDay }
        }
        let anchorDay = calendar.component(.day, from: anchor)
        return candidateDay == min(anchorDay, daysInMonth)
    }
}
