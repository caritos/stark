// ios/Tests/StarkKitTests/WeekRowTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("MonthGrid.weekRow")
struct WeekRowTests {
    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }

    @Test("the row of a mid-month date is its Sunday-first week, all in the month")
    func midMonth() {
        let row = MonthGrid.weekRow(containing: d("2026-09-21"))

        #expect(row.map(\.iso) == ["2026-09-20", "2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24", "2026-09-25", "2026-09-26"])
        #expect(row.allSatisfy { $0.isInMonth })
    }

    @Test("a week that straddles two months flags the days of the other month, relative to the date's month")
    func straddlingMonths() {
        let september = MonthGrid.weekRow(containing: d("2026-09-01"))
        #expect(september.map(\.iso) == ["2026-08-30", "2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05"])
        #expect(september.map(\.isInMonth) == [false, false, true, true, true, true, true])

        let august = MonthGrid.weekRow(containing: d("2026-08-31"))
        #expect(august.map(\.iso) == september.map(\.iso))
        #expect(august.map(\.isInMonth) == [true, true, false, false, false, false, false])
    }

    @Test("a Sunday starts its own row and a Saturday ends it")
    func weekBoundaries() {
        #expect(MonthGrid.weekRow(containing: d("2026-09-20")).first?.iso == "2026-09-20")
        #expect(MonthGrid.weekRow(containing: d("2026-09-26")).first?.iso == "2026-09-20")
        #expect(MonthGrid.weekRow(containing: d("2026-09-26")).last?.iso == "2026-09-26")
    }

    @Test("the row crosses the year boundary")
    func yearBoundary() {
        let row = MonthGrid.weekRow(containing: d("2026-12-31"))

        #expect(row.first?.iso == "2026-12-27")
        #expect(row.last?.iso == "2027-01-02")
        #expect(row.map(\.isInMonth) == [true, true, true, true, true, false, false])
    }

    @Test("weekStepped moves by whole weeks across month and year boundaries and returns local noon")
    func stepped() {
        #expect(MonthGrid.weekStepped(d("2026-09-21"), by: 1) == d("2026-09-28"))
        #expect(MonthGrid.weekStepped(d("2026-09-21"), by: -1) == d("2026-09-14"))
        #expect(MonthGrid.weekStepped(d("2026-09-28"), by: 1) == d("2026-10-05"))
        #expect(MonthGrid.weekStepped(d("2026-12-30"), by: 1) == d("2027-01-06"))
        #expect(MonthGrid.weekStepped(d("2026-09-21"), by: 0) == d("2026-09-21"))
    }
}
