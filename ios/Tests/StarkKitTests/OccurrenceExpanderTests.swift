// ios/Tests/StarkKitTests/OccurrenceExpanderTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("OccurrenceExpander")
struct OccurrenceExpanderTests {
    private let cal = Calendar(identifier: .gregorian)

    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }
    private func range(_ from: String, _ to: String) -> ClosedRange<Date> { d(from)...d(to) }

    @Test("non-recurring anchor appears only if inside the range")
    func nonRecurring() {
        let inRange = OccurrenceExpander.occurrences(anchor: d("2026-09-10"), rule: nil, exceptionDates: [], in: range("2026-09-01", "2026-09-30"))
        #expect(inRange == [d("2026-09-10")])

        let outOfRange = OccurrenceExpander.occurrences(anchor: d("2026-08-10"), rule: nil, exceptionDates: [], in: range("2026-09-01", "2026-09-30"))
        #expect(outOfRange.isEmpty)
    }

    @Test("daily every N days")
    func dailyInterval() {
        let rule = RecurrenceRule(frequency: .daily, interval: 2)
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-09-07"))
        #expect(dates == [d("2026-09-01"), d("2026-09-03"), d("2026-09-05"), d("2026-09-07")])
    }

    @Test("weekly on specific weekdays")
    func weeklyByDay() {
        // 2026-09-01 is a Tuesday; recur Mon/Wed/Fri.
        let rule = RecurrenceRule(frequency: .weekly, byDay: [.monday, .wednesday, .friday])
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-09-11"))
        #expect(dates == [d("2026-09-02"), d("2026-09-04"), d("2026-09-07"), d("2026-09-09"), d("2026-09-11")])
    }

    @Test("monthly clamps day-of-month to the shorter month")
    func monthlyClamped() {
        let rule = RecurrenceRule(frequency: .monthly, byMonthDay: [31])
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-01-31"), rule: rule, exceptionDates: [], in: range("2026-01-31", "2026-04-30"))
        #expect(dates == [d("2026-01-31"), d("2026-02-28"), d("2026-03-31"), d("2026-04-30")])
    }

    @Test("monthly matches any of several days-of-month")
    func monthlyMultipleDays() {
        let rule = RecurrenceRule(frequency: .monthly, byMonthDay: [1, 15])
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-10-31"))
        #expect(dates == [d("2026-09-01"), d("2026-09-15"), d("2026-10-01"), d("2026-10-15")])
    }

    @Test("yearly clamps Feb 29 to Feb 28 in a non-leap year")
    func yearlyLeapClamp() {
        let rule = RecurrenceRule(frequency: .yearly)
        let dates = OccurrenceExpander.occurrences(anchor: d("2024-02-29"), rule: rule, exceptionDates: [], in: range("2025-01-01", "2026-12-31"))
        #expect(dates == [d("2025-02-28"), d("2026-02-28")])
    }

    @Test("yearly matches any of several months")
    func yearlyMultipleMonths() {
        let rule = RecurrenceRule(frequency: .yearly, byMonth: [.march, .september])
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-03-15"), rule: rule, exceptionDates: [], in: range("2026-01-01", "2026-12-31"))
        #expect(dates == [d("2026-03-15"), d("2026-09-15")])
    }

    @Test("until excludes occurrences after the cutoff")
    func untilCutoff() {
        let rule = RecurrenceRule(frequency: .daily, until: d("2026-09-03"))
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-09-10"))
        #expect(dates == [d("2026-09-01"), d("2026-09-02"), d("2026-09-03")])
    }

    @Test("count limits the total number of occurrences")
    func countLimit() {
        let rule = RecurrenceRule(frequency: .daily, count: 2)
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-09-10"))
        #expect(dates == [d("2026-09-01"), d("2026-09-02")])
    }

    @Test("an anchor far before the range still produces the exact same occurrences (fast-forward optimization)")
    func fastForwardDoesNotChangeOutputForDistantAnchor() {
        // Same rule/range as "weekly on specific weekdays", but anchored a year earlier
        // instead of aligned to the range start — this exercises the `count == nil`
        // fast-forward path in OccurrenceExpander without changing the expected output.
        let rule = RecurrenceRule(frequency: .weekly, byDay: [.monday, .wednesday, .friday])
        let dates = OccurrenceExpander.occurrences(anchor: d("2025-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-09-11"))
        #expect(dates == [d("2026-09-02"), d("2026-09-04"), d("2026-09-07"), d("2026-09-09"), d("2026-09-11")])
    }

    @Test("count is still honored correctly when the anchor is far before the range (no fast-forward)")
    func countStillWalksFromAnchor() {
        // With `count` set, the walk must still start at `anchor` — fast-forwarding into
        // the range would lose track of how many occurrences already happened before it,
        // and produce the wrong subset (or none) instead of correctly stopping after 2.
        let rule = RecurrenceRule(frequency: .daily, count: 2)
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-05", "2026-09-10"))
        #expect(dates.isEmpty)
    }

    @Test("exceptionDates skips a specific occurrence")
    func exceptionDatesSkip() {
        let rule = RecurrenceRule(frequency: .daily)
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [d("2026-09-02")], in: range("2026-09-01", "2026-09-03"))
        #expect(dates == [d("2026-09-01"), d("2026-09-03")])
    }

    @Test("monthly positional: 2nd Tuesday of the month")
    func monthlyPositionalSpecificWeekday() {
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .second, dayType: .weekday(.tuesday))])
        // 2026-09-01 is a Tuesday; the 2nd Tuesday of September 2026 is the 8th.
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-11-30"))
        #expect(dates == [d("2026-09-08"), d("2026-10-13"), d("2026-11-10")])
    }

    @Test("monthly positional: last weekday of the month (generic day-type + BYSETPOS-style resolution)")
    func monthlyPositionalGenericWeekday() {
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .last, dayType: .weekdayOnly)])
        // September 2026's last day (30th) is a Wednesday, so the last weekday IS the 30th.
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-09-30"))
        #expect(dates == [d("2026-09-30")])
    }

    @Test("yearly positional combined with byMonth: 4th Thursday of November (Thanksgiving)")
    func yearlyPositionalWithMonth() {
        let rule = RecurrenceRule(frequency: .yearly, byPositionalDay: [PositionalDay(position: .fourth, dayType: .weekday(.thursday))], byMonth: [.november])
        // 2026-11-26 is the 4th Thursday of November 2026.
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-01-01"), rule: rule, exceptionDates: [], in: range("2026-01-01", "2027-12-31"))
        #expect(dates == [d("2026-11-26"), d("2027-11-25")])
    }

    @Test("4th position resolves correctly at the minimum-occurrence boundary (28-day February)")
    func positionalFourthAtMinimumBoundary() {
        // Every weekday occurs at least 4 times in every possible month length (28-31 days) -
        // a 28-day month is the tightest case, where every weekday occurs exactly 4 times.
        // This is the boundary `resolvePositionalDay`'s .fourth case must get exactly right;
        // there is no realistic month/weekday combination where .fourth fails to resolve at all
        // (that would require 5 supported positions, which this model doesn't have).
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .fourth, dayType: .weekday(.monday))])
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-02-01"), rule: rule, exceptionDates: [], in: range("2026-02-01", "2026-02-28"))
        // February 2026 Mondays: 2, 9, 16, 23 — exactly 4, so the 4th Monday (23rd) is the last one.
        #expect(dates == [d("2026-02-23")])
    }

    @Test("byPositionalDay takes precedence over byMonthDay when both are set")
    func positionalTakesPrecedenceOverMonthDay() {
        let rule = RecurrenceRule(frequency: .monthly, byMonthDay: [1], byPositionalDay: [PositionalDay(position: .second, dayType: .weekday(.tuesday))])
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-09-30"))
        // Should resolve via byPositionalDay (Sept 8), not byMonthDay (Sept 1).
        #expect(dates == [d("2026-09-08")])
    }
}
