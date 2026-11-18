import Foundation
import Testing
@testable import StarkKit

@Suite struct WidgetRowTextTests {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }()
    private let us = Locale(identifier: "en_US")

    private func d(_ day: Int, _ h: Int = 0, _ m: Int = 0, month: Int = 6) -> Date {
        Self.cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: h, minute: m))!
    }

    private func item(reminder: Bool = false, allDay: Bool = false, overdue: Bool = false, start: Date? = nil,
                      tomorrow: Bool = false) -> WidgetItem {
        WidgetItem(id: "x", title: "Title", isReminder: reminder, isAllDay: allDay, start: start ?? d(15, 14, 30),
                   end: nil, colorHex: nil, isOverdue: overdue, isTomorrow: tomorrow)
    }

    @Test func tomorrowsItemsSayTomorrow() {
        let timed = WidgetRowText.time(item(tomorrow: true), calendar: Self.cal, locale: us)
        #expect(timed?.hasPrefix("Tmrw") == true && timed?.contains("2:30") == true)
        #expect(WidgetRowText.time(item(allDay: true, tomorrow: true), calendar: Self.cal, locale: us) == "Tomorrow")
        let label = WidgetRowText.accessibilityLabel(item(tomorrow: true), calendar: Self.cal, locale: us)
        #expect(label.contains("tomorrow"))
        let allDay = WidgetRowText.accessibilityLabel(item(allDay: true, tomorrow: true), calendar: Self.cal, locale: us)
        #expect(allDay == "Event, Title, tomorrow, all day")
    }

    @Test func timedEventShowsTheClockTime() {
        let t = WidgetRowText.time(item(), calendar: Self.cal, locale: us)
        #expect(t?.contains("2:30") == true)
    }

    @Test func allDayEventSaysAllDay() {
        #expect(WidgetRowText.time(item(allDay: true), calendar: Self.cal, locale: us) == "All day")
    }

    @Test func dateOnlyReminderDueTodayHasNoTimeLine() {
        #expect(WidgetRowText.time(item(reminder: true, allDay: true), calendar: Self.cal, locale: us) == nil)
    }

    @Test func overdueReminderShowsTheMissedDate() {
        let t = WidgetRowText.time(item(reminder: true, allDay: true, overdue: true, start: d(1)),
                                   calendar: Self.cal, locale: us)
        #expect(t == "Jun 1")
    }

    @Test func labelsNameTheKindTitleAndTiming() {
        let ev = WidgetRowText.accessibilityLabel(item(), calendar: Self.cal, locale: us)
        #expect(ev.hasPrefix("Event, Title, ") && ev.contains("2:30"))
        let od = WidgetRowText.accessibilityLabel(item(reminder: true, allDay: true, overdue: true, start: d(1)),
                                                  calendar: Self.cal, locale: us)
        #expect(od == "Reminder, Title, overdue since Jun 1")
        #expect(WidgetRowText.accessibilityLabel(item(allDay: true), calendar: Self.cal, locale: us) == "Event, Title, all day")
        #expect(WidgetRowText.accessibilityLabel(item(reminder: true, allDay: true), calendar: Self.cal, locale: us)
                == "Reminder, Title, due today")
    }
}
