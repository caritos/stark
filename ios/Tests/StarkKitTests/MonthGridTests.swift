// ios/Tests/StarkKitTests/MonthGridTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("MonthGrid")
struct MonthGridTests {
    private let cal = Calendar(identifier: .gregorian)

    @Test("September 2026 (starts on a Tuesday): Aug 30-31 lead, Oct 1-10 trail, 42 cells")
    func september2026() {
        let days = MonthGrid.days(for: YearMonth(year: 2026, month0: 8))

        #expect(days.count == 42)
        #expect(days.count == MonthGrid.dayCount)
        #expect(days[0].iso == "2026-08-30")
        #expect(!days[0].isInMonth)
        #expect(!days[1].isInMonth)
        #expect(days[2].iso == "2026-09-01")
        #expect(days[2].isInMonth)
        #expect(days[31].iso == "2026-09-30")
        #expect(days[31].isInMonth)
        #expect(days[32].iso == "2026-10-01")
        #expect(!days[32].isInMonth)
        #expect(days[41].iso == "2026-10-10")
        #expect(days.filter(\.isInMonth).count == 30)
        #expect(DateMath.weekday(year: days[0].year, month0: days[0].month0, day: days[0].day) == 0)
    }

    @Test("a month that starts on Sunday has no leading days and a full trailing fortnight")
    func februaryStartsOnSunday() {
        let days = MonthGrid.days(for: YearMonth(year: 2026, month0: 1))

        #expect(days[0].iso == "2026-02-01")
        #expect(days[0].isInMonth)
        #expect(days[27].iso == "2026-02-28")
        #expect(days[28].iso == "2026-03-01")
        #expect(!days[28].isInMonth)
        #expect(days[41].iso == "2026-03-14")
    }

    @Test("a month that starts on Saturday has six leading days")
    func augustStartsOnSaturday() {
        let days = MonthGrid.days(for: YearMonth(year: 2026, month0: 7))

        #expect(days[0].iso == "2026-07-26")
        #expect(days[5].iso == "2026-07-31")
        #expect(!days[5].isInMonth)
        #expect(days[6].iso == "2026-08-01")
        #expect(days[6].isInMonth)
        #expect(days[41].iso == "2026-09-05")
    }

    @Test("the grid crosses year boundaries in both directions")
    func yearBoundaries() {
        let december = MonthGrid.days(for: YearMonth(year: 2026, month0: 11))
        #expect(december[0].iso == "2026-11-29")
        #expect(december[41].iso == "2027-01-09")
        #expect(december[41].year == 2027)
        #expect(december[41].month0 == 0)

        let january = MonthGrid.days(for: YearMonth(year: 2026, month0: 0))
        #expect(january[0].iso == "2025-12-28")
        #expect(january[0].year == 2025)
        #expect(january[0].month0 == 11)
    }

    @Test("a cell's id is its ISO date and its date is local noon of that day")
    func idAndDate() {
        let day = MonthGrid.days(for: YearMonth(year: 2026, month0: 8))[2]

        #expect(day.id == "2026-09-01")
        #expect(day.date == DateMath.date(from: "2026-09-01"))
    }

    @Test("cells built from the same year/month/day/isInMonth are equal and hash alike; iso is derived from them")
    func equalityWithStoredIso() {
        let a = GridDay(year: 2026, month0: 8, day: 1, isInMonth: true)
        let b = GridDay(year: 2026, month0: 8, day: 1, isInMonth: true)

        #expect(a == b)
        #expect(Set([a, b]).count == 1)
        #expect(a.iso == "2026-09-01")
        #expect(a != GridDay(year: 2026, month0: 8, day: 1, isInMonth: false))
    }

    @Test("the range runs from the start of the first cell's day to the last second of the last cell's day")
    func range() {
        let range = MonthGrid.range(for: YearMonth(year: 2026, month0: 8))

        #expect(range.lowerBound == cal.startOfDay(for: DateMath.date(from: "2026-08-30")))
        #expect(range.upperBound == cal.startOfDay(for: DateMath.date(from: "2026-10-11")).addingTimeInterval(-1))
        #expect(range.contains(DateMath.date(from: "2026-08-30")))
        #expect(range.contains(DateMath.date(from: "2026-10-10")))
        #expect(!range.contains(DateMath.date(from: "2026-10-11")))
    }
}
