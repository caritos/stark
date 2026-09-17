// ios/Tests/StarkKitTests/DateMathTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("DateMath")
struct DateMathTests {
    @Test("addDays crosses a month boundary")
    func addDaysCrossesMonth() {
        #expect(DateMath.addDays("2026-01-30", 3) == "2026-02-02")
    }

    @Test("daysInMonth accounts for leap years")
    func daysInMonthLeapYear() {
        #expect(DateMath.daysInMonth(year: 2024, month0: 1) == 29)
        #expect(DateMath.daysInMonth(year: 2026, month0: 1) == 28)
    }

    @Test("weekday matches a known date")
    func weekdayKnownDate() {
        // 2026-09-17 is a Thursday (4 = Thu, 0 = Sun)
        #expect(DateMath.weekday(year: 2026, month0: 8, day: 17) == 4)
    }

    @Test("isoDate round-trips through date(from:)")
    func isoDateRoundTrip() {
        let date = DateMath.date(from: "2026-09-17")
        #expect(DateMath.isoDate(from: date) == "2026-09-17")
    }
}

@Suite("YearMonth")
struct YearMonthTests {
    @Test("fileName formats as YYYY-MM.ics")
    func fileNameFormat() {
        #expect(YearMonth(year: 2026, month0: 8).fileName == "2026-09.ics")
    }

    @Test("orders chronologically across a year boundary")
    func ordersAcrossYearBoundary() {
        #expect(YearMonth(year: 2025, month0: 11) < YearMonth(year: 2026, month0: 0))
    }

    @Test("normalizes an out-of-range month0 across a year boundary")
    func normalizesOutOfRangeMonth0() {
        // PlannerStore.start() computes center.month0 ± 1, which can land on -1 or 12.
        #expect(YearMonth(year: 2026, month0: -1) == YearMonth(year: 2025, month0: 11))
        #expect(YearMonth(year: 2026, month0: 12) == YearMonth(year: 2027, month0: 0))
    }
}
