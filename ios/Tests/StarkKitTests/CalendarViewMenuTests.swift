import Testing
@testable import StarkKit

@Suite struct CalendarViewMenuTests {
    @Test func currentIsMonthWhenFullMonthShown() {
        for m in [CalendarMode.week, .month, .year] {
            #expect(CalendarViewMenu.current(for: m, fullMonth: true) == .month)
        }
    }

    @Test func currentFollowsModeOtherwise() {
        #expect(CalendarViewMenu.current(for: .week, fullMonth: false) == .dayTicker)
        #expect(CalendarViewMenu.current(for: .month, fullMonth: false) == .dayTicker)
        #expect(CalendarViewMenu.current(for: .year, fullMonth: false) == .year)
    }

    @Test func chooseMonthKeepsModeAndTurnsFullMonthOn() {
        for m in [CalendarMode.week, .month, .year] {
            let t = CalendarViewMenu.target(after: .month, current: m)
            // Year would cover Month, so the strip below becomes the month grid.
            #expect(t.mode == (m == .year ? .month : m))
            #expect(t.fullMonth)
        }
    }

    @Test func chooseYearTurnsFullMonthOff() {
        for m in [CalendarMode.week, .month, .year] {
            let t = CalendarViewMenu.target(after: .year, current: m)
            #expect(t.mode == .year)
            #expect(!t.fullMonth)
        }
    }

    @Test func chooseDayTickerFromYearGivesMonthAndFullMonthOff() {
        let t = CalendarViewMenu.target(after: .dayTicker, current: .year)
        #expect(t.mode == .month)
        #expect(!t.fullMonth)
    }

    @Test func chooseDayTickerKeepsWeekAndMonth() {
        let w = CalendarViewMenu.target(after: .dayTicker, current: .week)
        #expect(w.mode == .week && !w.fullMonth)
        let m = CalendarViewMenu.target(after: .dayTicker, current: .month)
        #expect(m.mode == .month && !m.fullMonth)
    }

    @Test func accessibilityValueNamesCurrentView() {
        #expect(CalendarViewMenu.accessibilityValue(for: .week, fullMonth: false) == "DayTicker")
        #expect(CalendarViewMenu.accessibilityValue(for: .month, fullMonth: false) == "DayTicker")
        #expect(CalendarViewMenu.accessibilityValue(for: .year, fullMonth: false) == "Year")
        #expect(CalendarViewMenu.accessibilityValue(for: .week, fullMonth: true) == "Month")
    }

    @Test func allChoicesHaveUniqueTitleAndImage() {
        let all = CalendarViewChoice.allCases
        #expect(all.allSatisfy { !$0.title.isEmpty && !$0.systemImage.isEmpty })
        #expect(Set(all.map(\.title)).count == all.count)
        #expect(Set(all.map(\.systemImage)).count == all.count)
    }

    @Test func menuOrderIsDayTickerMonthYear() {
        #expect(CalendarViewChoice.allCases == [.dayTicker, .month, .year])
    }
}
