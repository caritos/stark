import Testing
@testable import StarkKit

@Suite struct CalendarViewMenuTests {
    @Test func currentForEachMode() {
        #expect(CalendarViewMenu.current(for: .week) == .dayTicker)
        #expect(CalendarViewMenu.current(for: .month) == .dayTicker)
        #expect(CalendarViewMenu.current(for: .year) == .year)
    }

    @Test func chooseYearFromAnyMode() {
        for m in [CalendarMode.week, .month, .year] {
            #expect(CalendarViewMenu.mode(after: .year, current: m) == .year)
        }
    }

    @Test func chooseDayTickerFromYearGivesMonth() {
        #expect(CalendarViewMenu.mode(after: .dayTicker, current: .year) == .month)
    }

    @Test func chooseDayTickerKeepsWeekAndMonth() {
        #expect(CalendarViewMenu.mode(after: .dayTicker, current: .week) == .week)
        #expect(CalendarViewMenu.mode(after: .dayTicker, current: .month) == .month)
    }

    @Test func accessibilityValueNamesCurrentView() {
        #expect(CalendarViewMenu.accessibilityValue(for: .week) == "DayTicker")
        #expect(CalendarViewMenu.accessibilityValue(for: .month) == "DayTicker")
        #expect(CalendarViewMenu.accessibilityValue(for: .year) == "Year")
    }

    @Test func allChoicesHaveTitleAndImage() {
        let all = CalendarViewChoice.allCases
        #expect(all.allSatisfy { !$0.title.isEmpty && !$0.systemImage.isEmpty })
        #expect(Set(all.map(\.title)).count == all.count)
    }
}
