// ios/Tests/StarkKitTests/CalendarModeTests.swift
import Testing
@testable import StarkKit

@Suite("CalendarMode")
struct CalendarModeTests {
    @Test("expanding and collapsing walk week <-> month <-> year and stop at the ends")
    func walk() {
        #expect(CalendarMode.week.expanded == .month)
        #expect(CalendarMode.month.expanded == .year)
        #expect(CalendarMode.year.expanded == nil)
        #expect(CalendarMode.year.collapsed == .month)
        #expect(CalendarMode.month.collapsed == .week)
        #expect(CalendarMode.week.collapsed == nil)
    }

    @Test("a drag past the distance threshold changes the mode: down expands, up collapses")
    func dragByDistance() {
        #expect(CalendarMode.month.afterDrag(translation: 40, predictedEnd: 40) == .year)
        #expect(CalendarMode.month.afterDrag(translation: -40, predictedEnd: -40) == .week)
        #expect(CalendarMode.week.afterDrag(translation: 40, predictedEnd: 40) == .month)
        #expect(CalendarMode.year.afterDrag(translation: -40, predictedEnd: -40) == .month)
        #expect(CalendarMode.month.afterDrag(translation: CalendarMode.dragThreshold, predictedEnd: 0) == .year)
    }

    @Test("a short, slow drag changes nothing")
    func shortDrag() {
        #expect(CalendarMode.month.afterDrag(translation: 10, predictedEnd: 20) == .month)
        #expect(CalendarMode.month.afterDrag(translation: -10, predictedEnd: -20) == .month)
        #expect(CalendarMode.month.afterDrag(translation: 29.9, predictedEnd: 99.9) == .month)
    }

    @Test("a short but fast fling changes the mode by its predicted travel")
    func fling() {
        #expect(CalendarMode.month.afterDrag(translation: 12, predictedEnd: 150) == .year)
        #expect(CalendarMode.month.afterDrag(translation: -12, predictedEnd: -150) == .week)
        #expect(CalendarMode.month.afterDrag(translation: 0, predictedEnd: CalendarMode.flingThreshold) == .year)
    }

    @Test("a drag past an end mode stays put")
    func ends() {
        #expect(CalendarMode.year.afterDrag(translation: 40, predictedEnd: 40) == .year)
        #expect(CalendarMode.week.afterDrag(translation: -40, predictedEnd: -40) == .week)
    }

    @Test("titles are what VoiceOver reads")
    func titles() {
        #expect(CalendarMode.week.title == "Week")
        #expect(CalendarMode.month.title == "Month")
        #expect(CalendarMode.year.title == "Year")
    }
}
