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
}
