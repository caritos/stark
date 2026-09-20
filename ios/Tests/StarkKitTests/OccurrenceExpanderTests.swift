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

    /// A non-midnight time-of-day, on the given ISO calendar day - mirrors a real anchor created
    /// via AddItemView's DatePicker (which always carries an actual time), unlike `d(_:)`'s fixed
    /// noon.
    private func dt(_ iso: String, hour: Int, minute: Int) -> Date {
        let c = DateMath.components(iso)
        return cal.date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: hour, minute: minute))!
    }

    @Test("until at day granularity: a non-midnight anchor still gets its final day's occurrence, not cut off by midnight-vs-time-of-day")
    func untilIncludesFinalDayDespiteNonMidnightAnchor() {
        // `until` is always encoded/decoded date-only (local midnight), but a real anchor almost
        // always carries a non-midnight time-of-day. A raw datetime comparison
        // (candidate > until) would judge 2026-09-05T15:42 as later than 2026-09-05T00:00 and
        // wrongly cut off the last intended occurrence.
        let anchor = dt("2026-09-01", hour: 15, minute: 42)
        let until = dt("2026-09-05", hour: 0, minute: 0) // decoded from a date-only UNTIL=20260905
        let rule = RecurrenceRule(frequency: .daily, until: until)
        let dates = OccurrenceExpander.occurrences(anchor: anchor, rule: rule, exceptionDates: [], in: dt("2026-09-01", hour: 0, minute: 0)...dt("2026-09-10", hour: 0, minute: 0))
        #expect(dates.count == 5)
        #expect(dates.last == dt("2026-09-05", hour: 15, minute: 42))
    }

    // MARK: - Fast-forward must preserve the anchor's time-of-day and alignment

    /// Asserts the returned occurrences fall on exactly `days`, every one at 09:30 (the anchor's
    /// time-of-day), regardless of the time-of-day the display range starts at.
    private func expectNineThirty(_ dates: [Date], on days: [String], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(dates.map { DateMath.isoDate(from: $0) } == days, sourceLocation: sourceLocation)
        for date in dates {
            let parts = cal.dateComponents([.hour, .minute, .second], from: date)
            #expect(parts.hour == 9 && parts.minute == 30 && parts.second == 0, "\(date) should be 09:30:00", sourceLocation: sourceLocation)
        }
    }

    @Test("weekly: a far-before anchor keeps 09:30 whether the range starts at noon or at midnight")
    func weeklyKeepsAnchorTimeOfDay() {
        // 2026-01-05 is a Monday; Sep 14 2026 is exactly 36 weeks later, so Mondays align.
        let anchor = dt("2026-01-05", hour: 9, minute: 30)
        let rule = RecurrenceRule(frequency: .weekly)
        let end = dt("2026-10-14", hour: 12, minute: 0)

        // Noon start: Sep 14 09:30 is before the range and must be trimmed.
        let noon = OccurrenceExpander.occurrences(anchor: anchor, rule: rule, exceptionDates: [], in: dt("2026-09-14", hour: 12, minute: 0)...end)
        expectNineThirty(noon, on: ["2026-09-21", "2026-09-28", "2026-10-05", "2026-10-12"])

        // Midnight start: Sep 14 09:30 is inside the range.
        let midnight = OccurrenceExpander.occurrences(anchor: anchor, rule: rule, exceptionDates: [], in: dt("2026-09-14", hour: 0, minute: 0)...end)
        expectNineThirty(midnight, on: ["2026-09-14", "2026-09-21", "2026-09-28", "2026-10-05", "2026-10-12"])
    }

    @Test("daily interval 2: a far-before anchor keeps 09:30 AND the every-other-day alignment")
    func dailyIntervalKeepsAnchorAlignment() {
        // Sep 14 2026 is 252 days after the anchor (even), so the occurrence days are the even
        // offsets: Sep 14, 16, 18, 20, 22, ...
        let anchor = dt("2026-01-05", hour: 9, minute: 30)
        let rule = RecurrenceRule(frequency: .daily, interval: 2)

        let noon = OccurrenceExpander.occurrences(anchor: anchor, rule: rule, exceptionDates: [], in: dt("2026-09-15", hour: 12, minute: 0)...dt("2026-09-23", hour: 12, minute: 0))
        expectNineThirty(noon, on: ["2026-09-16", "2026-09-18", "2026-09-20", "2026-09-22"])

        // Midnight start: with the bug the day-difference is computed from a 00:00 candidate
        // against a 09:30 anchor and rounds down, flipping the parity onto the wrong days.
        let midnight = OccurrenceExpander.occurrences(anchor: anchor, rule: rule, exceptionDates: [], in: dt("2026-09-15", hour: 0, minute: 0)...dt("2026-09-23", hour: 12, minute: 0))
        expectNineThirty(midnight, on: ["2026-09-16", "2026-09-18", "2026-09-20", "2026-09-22"])
    }

    @Test("monthly interval 2: a far-before anchor keeps 09:30 AND the every-other-month alignment")
    func monthlyIntervalKeepsAnchorAlignment() {
        // Anchor Jan 15: matching months are Jan, Mar, May, Jul, Sep, Nov.
        let anchor = dt("2026-01-15", hour: 9, minute: 30)
        let rule = RecurrenceRule(frequency: .monthly, interval: 2)
        let end = dt("2026-10-20", hour: 12, minute: 0)

        let noon = OccurrenceExpander.occurrences(anchor: anchor, rule: rule, exceptionDates: [], in: dt("2026-06-20", hour: 12, minute: 0)...end)
        expectNineThirty(noon, on: ["2026-07-15", "2026-09-15"])

        // Midnight start on the 15th itself: the 09:30 Jul 15 occurrence is inside the range.
        // With the bug the month-difference from the 09:30 anchor to a 00:00 candidate rounds
        // down to 5 (odd), so Jul 15 is wrongly rejected.
        let midnight = OccurrenceExpander.occurrences(anchor: anchor, rule: rule, exceptionDates: [], in: dt("2026-07-15", hour: 0, minute: 0)...end)
        expectNineThirty(midnight, on: ["2026-07-15", "2026-09-15"])
    }

    @Test("yearly interval 2: a far-before anchor keeps 09:30 AND the every-other-year alignment")
    func yearlyIntervalKeepsAnchorAlignment() {
        // Anchor Mar 10 2020: matching years are 2020, 2022, 2024, 2026, 2028, 2030.
        let anchor = dt("2020-03-10", hour: 9, minute: 30)
        let rule = RecurrenceRule(frequency: .yearly, interval: 2)
        let end = dt("2030-12-31", hour: 12, minute: 0)

        let noon = OccurrenceExpander.occurrences(anchor: anchor, rule: rule, exceptionDates: [], in: dt("2026-01-01", hour: 12, minute: 0)...end)
        expectNineThirty(noon, on: ["2026-03-10", "2028-03-10", "2030-03-10"])

        let midnight = OccurrenceExpander.occurrences(anchor: anchor, rule: rule, exceptionDates: [], in: dt("2026-01-01", hour: 0, minute: 0)...end)
        expectNineThirty(midnight, on: ["2026-03-10", "2028-03-10", "2030-03-10"])
    }

    @Test("control: a count-limited rule (which walks from the anchor) already keeps 09:30")
    func countLimitedKeepsAnchorTimeOfDay() {
        // 30 daily occurrences: Sep 1 ... Sep 30. Range starts at noon on Sep 10, so Sep 10
        // 09:30 is trimmed and Sep 11 ... Sep 30 remain.
        let anchor = dt("2026-09-01", hour: 9, minute: 30)
        let rule = RecurrenceRule(frequency: .daily, count: 30)
        let dates = OccurrenceExpander.occurrences(anchor: anchor, rule: rule, exceptionDates: [], in: dt("2026-09-10", hour: 12, minute: 0)...dt("2026-10-05", hour: 12, minute: 0))
        expectNineThirty(dates, on: (11...30).map { String(format: "2026-09-%02d", $0) })
    }

    @Test("fast-forward keeps until and exception dates day-granular")
    func fastForwardKeepsUntilAndExceptionsDayGranular() {
        let anchor = dt("2026-01-05", hour: 9, minute: 30)
        // `until` decodes date-only (midnight): the Oct 5 09:30 occurrence must still be included.
        let rule = RecurrenceRule(frequency: .weekly, until: dt("2026-10-05", hour: 0, minute: 0))
        // The exception date carries a different time-of-day than the occurrence (noon vs 09:30).
        let exceptions = [dt("2026-09-28", hour: 12, minute: 0)]
        let dates = OccurrenceExpander.occurrences(anchor: anchor, rule: rule, exceptionDates: exceptions, in: dt("2026-09-14", hour: 12, minute: 0)...dt("2026-10-31", hour: 12, minute: 0))
        expectNineThirty(dates, on: ["2026-09-21", "2026-10-05"])
    }

    @Test("until round-trips through encode/decode and still includes the final day's occurrence for a non-midnight anchor")
    func untilEncodeDecodeExpandRoundTrip() {
        let anchor = dt("2026-09-01", hour: 15, minute: 42)
        let lastIntendedOccurrence = dt("2026-09-05", hour: 15, minute: 42)
        let rule = RecurrenceRule(frequency: .daily, until: lastIntendedOccurrence)

        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=DAILY;UNTIL=20260905") // date-only, decodes to local midnight

        let decoded = RRuleCodec.decode(encoded)!
        let dates = OccurrenceExpander.occurrences(
            anchor: anchor, rule: decoded, exceptionDates: [],
            in: dt("2026-09-01", hour: 0, minute: 0)...dt("2026-09-10", hour: 0, minute: 0)
        )
        #expect(dates.contains(lastIntendedOccurrence))
        #expect(dates.count == 5)
    }
}
