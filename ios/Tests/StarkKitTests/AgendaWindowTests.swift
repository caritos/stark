// ios/Tests/StarkKitTests/AgendaWindowTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("AgendaWindow")
struct AgendaWindowTests {
    @Test("the display range is a subset of the load range, and both include today")
    func displayRangeIsSubsetOfLoadRange() {
        let today = DateMath.date(from: "2026-09-20")
        let display = AgendaWindow.range(around: today)
        let load = AgendaWindow.loadRange(around: today)

        #expect(load.lowerBound <= display.lowerBound)
        #expect(load.upperBound >= display.upperBound)
        #expect(display.contains(today))
        #expect(load.contains(today))
    }

    @Test("the load range reaches back exactly overdueLookbackDays and forward daysAfter")
    func loadRangeBounds() {
        let today = DateMath.date(from: "2026-09-20")
        let load = AgendaWindow.loadRange(around: today)

        #expect(load.lowerBound == DateMath.date(from: DateMath.addDays("2026-09-20", -AgendaWindow.overdueLookbackDays)))
        #expect(load.upperBound == DateMath.date(from: DateMath.addDays("2026-09-20", AgendaWindow.daysAfter)))
    }

    @Test("the display range is unchanged: 14 days back, 60 days forward")
    func displayRangeUnchanged() {
        let today = DateMath.date(from: "2026-09-20")
        let display = AgendaWindow.range(around: today)

        #expect(display.lowerBound == DateMath.date(from: "2026-09-06"))
        #expect(display.upperBound == DateMath.date(from: "2026-11-19"))
    }
}
