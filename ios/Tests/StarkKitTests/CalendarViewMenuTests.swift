import Testing
@testable import StarkKit

@Suite struct CalendarViewMenuTests {
    @Test func currentIsMonthWhenFullMonthShown() {
        for m in [CalendarMode.week, .month, .year] {
            #expect(CalendarViewMenu.current(for: m, full: .month) == .month)
        }
    }

    @Test func currentIsQuarterWhenFullQuarterShown() {
        for m in [CalendarMode.week, .month, .year] {
            #expect(CalendarViewMenu.current(for: m, full: .quarter) == .quarter)
        }
    }

    @Test func currentFollowsModeOtherwise() {
        #expect(CalendarViewMenu.current(for: .week, full: .none) == .dayTicker)
        #expect(CalendarViewMenu.current(for: .month, full: .none) == .dayTicker)
        #expect(CalendarViewMenu.current(for: .year, full: .none) == .year)
    }

    @Test func chooseMonthKeepsModeAndTurnsFullMonthOn() {
        for m in [CalendarMode.week, .month, .year] {
            let t = CalendarViewMenu.target(after: .month, current: m)
            // Year would cover Month, so the strip below becomes the month grid.
            #expect(t.mode == (m == .year ? .month : m))
            #expect(t.full == .month)
        }
    }

    @Test func chooseQuarterKeepsModeAndTurnsFullQuarterOn() {
        for m in [CalendarMode.week, .month, .year] {
            let t = CalendarViewMenu.target(after: .quarter, current: m)
            #expect(t.mode == (m == .year ? .month : m))
            #expect(t.full == .quarter)
        }
    }

    @Test func monthAndQuarterSwitchEachOther() {
        // The target depends only on the mode, so Month <-> Quarter is a plain swap.
        let toQuarter = CalendarViewMenu.target(after: .quarter, current: .week)
        #expect(CalendarViewMenu.current(for: toQuarter.mode, full: toQuarter.full) == .quarter)
        let toMonth = CalendarViewMenu.target(after: .month, current: toQuarter.mode)
        #expect(toMonth.mode == .week && toMonth.full == .month)
        #expect(CalendarViewMenu.current(for: toMonth.mode, full: toMonth.full) == .month)
    }

    @Test func chooseYearTurnsFullOff() {
        for m in [CalendarMode.week, .month, .year] {
            let t = CalendarViewMenu.target(after: .year, current: m)
            #expect(t.mode == .year)
            #expect(t.full == .none)
        }
    }

    @Test func chooseDayTickerFromYearGivesMonthAndFullOff() {
        let t = CalendarViewMenu.target(after: .dayTicker, current: .year)
        #expect(t.mode == .month)
        #expect(t.full == .none)
    }

    @Test func chooseDayTickerKeepsWeekAndMonth() {
        let w = CalendarViewMenu.target(after: .dayTicker, current: .week)
        #expect(w.mode == .week && w.full == .none)
        let m = CalendarViewMenu.target(after: .dayTicker, current: .month)
        #expect(m.mode == .month && m.full == .none)
    }

    @Test func accessibilityValueNamesCurrentView() {
        #expect(CalendarViewMenu.accessibilityValue(for: .week, full: .none) == "DayTicker")
        #expect(CalendarViewMenu.accessibilityValue(for: .month, full: .none) == "DayTicker")
        #expect(CalendarViewMenu.accessibilityValue(for: .year, full: .none) == "Year")
        #expect(CalendarViewMenu.accessibilityValue(for: .week, full: .month) == "Month")
        #expect(CalendarViewMenu.accessibilityValue(for: .month, full: .quarter) == "Quarter")
    }

    @Test func quarterTitleAndImage() {
        #expect(CalendarViewChoice.quarter.title == "Quarter")
        #expect(CalendarViewChoice.quarter.systemImage == "rectangle.split.3x3")
    }

    @Test func allChoicesHaveUniqueTitleAndImage() {
        let all = CalendarViewChoice.allCases
        #expect(all.allSatisfy { !$0.title.isEmpty && !$0.systemImage.isEmpty })
        #expect(Set(all.map(\.title)).count == all.count)
        #expect(Set(all.map(\.systemImage)).count == all.count)
    }

    @Test func menuOrderIsDayTickerDayWeekMonthQuarterYear() {
        #expect(CalendarViewChoice.allCases == [.dayTicker, .day, .week, .month, .quarter, .year])
    }

    @Test func currentIsDayOrWeekWhenFullShown() {
        for m in [CalendarMode.week, .month, .year] {
            #expect(CalendarViewMenu.current(for: m, full: .day) == .day)
            #expect(CalendarViewMenu.current(for: m, full: .week) == .week)
        }
    }

    @Test func chooseDayAndWeekKeepModeUnderneath() {
        for m in [CalendarMode.week, .month, .year] {
            let d = CalendarViewMenu.target(after: .day, current: m)
            #expect(d.mode == (m == .year ? .month : m) && d.full == .day)
            let w = CalendarViewMenu.target(after: .week, current: m)
            #expect(w.mode == (m == .year ? .month : m) && w.full == .week)
        }
    }

    @Test func dayAndWeekTitlesImagesAndAccessibility() {
        #expect(CalendarViewChoice.day.title == "Day")
        #expect(CalendarViewChoice.week.title == "Week")
        #expect(CalendarViewChoice.day.systemImage == "rectangle.portrait")
        #expect(CalendarViewChoice.week.systemImage == "rectangle.split.3x1")
        #expect(CalendarViewMenu.accessibilityValue(for: .month, full: .day) == "Day")
        #expect(CalendarViewMenu.accessibilityValue(for: .month, full: .week) == "Week")
    }
}
