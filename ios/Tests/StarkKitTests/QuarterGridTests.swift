// ios/Tests/StarkKitTests/QuarterGridTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("QuarterGrid")
struct QuarterGridTests {
    private let cal = Calendar(identifier: .gregorian)
    private func weekday(_ d: GridDay) -> Int { DateMath.weekday(year: d.year, month0: d.month0, day: d.day) }

    @Test func ninetyOneDaysThirteenWeeks() {
        let days = QuarterGrid.days(startingAt: YearMonth(year: 2026, month0: 10))
        #expect(QuarterGrid.weekCount == 13)
        #expect(days.count == 91)
        #expect(days.count == QuarterGrid.weekCount * 7)
        // Consecutive days, every one in the quarter (no dimmed days).
        for i in 1..<days.count { #expect(days[i].iso == DateMath.addDays(days[i - 1].iso, 1)) }
        #expect(days.allSatisfy { $0.isInMonth })
    }

    @Test func november2026StartsOnItsFirstSunday() {
        // Nov 1 2026 is a Sunday: the quarter starts on it and ends Sat Jan 30 2027.
        let days = QuarterGrid.days(startingAt: YearMonth(year: 2026, month0: 10))
        #expect(days[0].iso == "2026-11-01")
        #expect(days[90].iso == "2027-01-30")
        #expect(weekday(days[0]) == 0)
    }

    @Test func monthStartingMidWeekStartsOnPrecedingSunday() {
        // Sep 1 2026 is a Tuesday -> Sun Aug 30.
        let days = QuarterGrid.days(startingAt: YearMonth(year: 2026, month0: 8))
        #expect(days[0].iso == "2026-08-30")
        #expect(weekday(days[0]) == 0)
        #expect(days[90].iso == "2026-11-28")
    }

    @Test func februaryNonLeapAndLeap() {
        // Feb 1 2027 is a Monday -> Sun Jan 31 2027; Feb has 28 days, Mar 1 is index 29.
        let d27 = QuarterGrid.days(startingAt: YearMonth(year: 2027, month0: 1))
        #expect(d27[0].iso == "2027-01-31")
        #expect(d27[29].iso == "2027-03-01")
        // Feb 1 2028 is a Tuesday -> Sun Jan 30 2028; Feb 29 exists, Mar 1 is index 31.
        let d28 = QuarterGrid.days(startingAt: YearMonth(year: 2028, month0: 1))
        #expect(d28[0].iso == "2028-01-30")
        #expect(d28[30].iso == "2028-02-29")
        #expect(d28[31].iso == "2028-03-01")
        #expect(weekday(d27[0]) == 0 && weekday(d28[0]) == 0)
    }

    @Test func monthStartsFindsEachFirst() {
        let days = QuarterGrid.days(startingAt: YearMonth(year: 2026, month0: 10))
        // Nov 1 (0), Dec 1 (30), Jan 1 (61).
        #expect(QuarterGrid.monthStarts(in: days) == [0, 30, 61])
        let sep = QuarterGrid.days(startingAt: YearMonth(year: 2026, month0: 8))
        // Aug 30 start: Sep 1 (2), Oct 1 (32), Nov 1 (63).
        #expect(QuarterGrid.monthStarts(in: sep) == [2, 32, 63])
    }

    @Test func titleSpansFirstAndLastMonthAcrossYearBoundary() {
        let t = QuarterGrid.title(for: YearMonth(year: 2026, month0: 10))
        #expect(t.first == "Nov 2026")
        #expect(t.second == "Jan 2027")
        // Sep 2026 (starts Aug 30, ends Nov 28): titled by the displayed month and two after.
        let s = QuarterGrid.title(for: YearMonth(year: 2026, month0: 8))
        #expect(s.first == "Sep 2026" && s.second == "Nov 2026")
    }

    @Test func monthStartLabel() {
        let days = QuarterGrid.days(startingAt: YearMonth(year: 2026, month0: 10))
        #expect(QuarterGrid.monthStartLabel(for: days[0]) == "Nov 1")
        #expect(QuarterGrid.monthStartLabel(for: days[30]) == "Dec 1")
        #expect(QuarterGrid.monthStartLabel(for: days[61]) == "Jan 1")
        #expect(QuarterGrid.monthStartLabel(for: days[1]) == nil)
    }

    @Test func seamsMarkMonthBoundaries() {
        // Dec 1 2026 is a Tuesday (index 30, row 4, col 2).
        let days = QuarterGrid.days(startingAt: YearMonth(year: 2026, month0: 10))
        // Leading seam on the 1st when it is not in column 0.
        #expect(QuarterGrid.seam(at: 30, in: days) == QuarterSeam(top: true, leading: true))
        // Days of December in row 4 after Dec 1: top seam (row above is November), no leading.
        #expect(QuarterGrid.seam(at: 31, in: days) == QuarterSeam(top: true, leading: false))
        // Nov 29/30 (row 4, cols 0-1): still November, no seam.
        #expect(QuarterGrid.seam(at: 28, in: days) == QuarterSeam(top: false, leading: false))
        // Row 5 cols 0-1 (Dec 6, 7): November above them -> top seam.
        #expect(QuarterGrid.seam(at: 35, in: days) == QuarterSeam(top: true, leading: false))
        #expect(QuarterGrid.seam(at: 36, in: days) == QuarterSeam(top: true, leading: false))
        // Row 5 col 2 (Dec 8): December above -> none.
        #expect(QuarterGrid.seam(at: 37, in: days) == QuarterSeam(top: false, leading: false))
        // First row never has a top seam; column 0 never a leading one.
        #expect(QuarterGrid.seam(at: 0, in: days) == QuarterSeam(top: false, leading: false))
        // Jan 1 2027 is a Friday (index 61, row 8 col 5).
        #expect(QuarterGrid.seam(at: 61, in: days) == QuarterSeam(top: true, leading: true))
    }

    @Test func rangeCoversAllNinetyOneDays() {
        for m in [YearMonth(year: 2026, month0: 10), YearMonth(year: 2028, month0: 1),
                  YearMonth(year: 2026, month0: 2)] {
            let days = QuarterGrid.days(startingAt: m)
            let r = QuarterGrid.range(for: m)
            #expect(r.lowerBound == cal.startOfDay(for: days[0].date))
            let lastStart = cal.startOfDay(for: days[90].date)
            #expect(r.contains(lastStart))
            #expect(r.contains(cal.date(bySettingHour: 23, minute: 59, second: 59, of: lastStart)!))
            let nextDay = cal.date(byAdding: .day, value: 1, to: lastStart)!
            #expect(!r.contains(nextDay))
            #expect(!r.contains(r.lowerBound.addingTimeInterval(-1)))
        }
    }
}
