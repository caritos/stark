import Foundation
import Testing
@testable import StarkKit

/// The Lock Screen families: the circular count and the one-line text of rectangular and inline.
@Suite struct WidgetLockScreenTests {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }()
    private let us = Locale(identifier: "en_US")

    private func date(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        Self.cal.date(from: DateComponents(year: 2026, month: 6, day: d, hour: h, minute: m))!
    }

    private var now: Date { date(15, 10) }

    private func info(_ id: String, list: Bool = false) -> AppleCalendarInfo {
        AppleCalendarInfo(id: id, title: id, accountName: "iCloud", colorHex: "#FF0000", isReminderList: list)
    }

    private func event(_ id: String, _ start: Date, _ end: Date?, allDay: Bool = false, cal: String = "cal1") -> AppleCalendarEvent {
        AppleCalendarEvent(id: id, title: id, notes: nil, location: nil, url: nil, start: start, end: end,
                           isAllDay: allDay, calendar: info(cal))
    }

    private func reminder(_ id: String, due: Date?, hasTime: Bool = true, done: Bool = false) -> AppleReminder {
        AppleReminder(id: id, title: id, notes: nil, due: due, dueHasTime: hasTime, isCompleted: done,
                      completedAt: nil, priority: nil, calendar: info("list1", list: true))
    }

    private func count(events: [AppleCalendarEvent] = [], reminders: [AppleReminder] = [],
                       excluded: Set<String> = []) -> Int {
        WidgetAgenda.remainingToday(events: events, reminders: reminders, excluded: excluded, now: now,
                                    calendar: Self.cal)
    }

    private func item(_ title: String = "Standup", allDay: Bool = false, reminder: Bool = false,
                      overdue: Bool = false, tomorrow: Bool = false) -> WidgetItem {
        WidgetItem(id: "x", title: title, isReminder: reminder, isAllDay: allDay, start: date(15, 9),
                   end: nil, colorHex: nil, isOverdue: overdue, isTomorrow: tomorrow)
    }

    // MARK: remainingToday

    @Test func nothingLeftIsZero() {
        #expect(count() == 0)
        #expect(count(events: [event("ended", date(15, 8), date(15, 9))]) == 0)
    }

    @Test func countsTodaysRemainingEventsAndDueReminders() {
        let n = count(events: [event("running", date(15, 9), date(15, 11)),
                               event("later", date(15, 14), date(15, 15)),
                               event("allday", date(15), date(15), allDay: true)],
                      reminders: [reminder("due", due: date(15, 17)),
                                  reminder("dateOnly", due: date(15), hasTime: false)])
        #expect(n == 5)
    }

    @Test func tomorrowsItemsAreNotCounted() {
        let n = count(events: [event("today", date(15, 14), date(15, 15)),
                               event("tmrw", date(16, 9), date(16, 10)),
                               event("tmrwAllDay", date(16), date(16), allDay: true)])
        #expect(n == 1)
    }

    @Test func everyOverdueReminderCountsNotOnlyTheCappedRows() {
        let overdue = (1...4).map { reminder("o\($0)", due: date($0, 9)) }
        #expect(count(events: [event("later", date(15, 14), date(15, 15))], reminders: overdue) == 5)
    }

    @Test func countIsNotCutAtFiveRows() {
        let many = (0..<12).map { event("e\($0)", date(15, 11, $0), date(15, 12, $0)) }
        #expect(count(events: many) == 12)
    }

    @Test func completedAndExcludedAreNotCounted() {
        let n = count(events: [event("hidden", date(15, 14), date(15, 15), cal: "hide")],
                      reminders: [reminder("done", due: date(15, 17), done: true)], excluded: ["hide"])
        #expect(n == 0)
    }

    // MARK: countText

    @Test func countTextCapsAtNinePlus() {
        #expect(WidgetRowText.countText(0) == "0")
        #expect(WidgetRowText.countText(9) == "9")
        #expect(WidgetRowText.countText(10) == "9+")
        #expect(WidgetRowText.countText(250) == "9+")
    }

    @Test func countAccessibilityLabel() {
        #expect(WidgetRowText.countAccessibilityLabel(0) == "Nothing left today")
        #expect(WidgetRowText.countAccessibilityLabel(1) == "1 item left today")
        #expect(WidgetRowText.countAccessibilityLabel(12) == "12 items left today")
    }

    // MARK: lockLine

    /// The formatter puts a narrow no-break space before AM/PM; compare with a plain space.
    private func plain(_ s: String?) -> String? { s?.replacingOccurrences(of: "\u{202F}", with: " ") }

    @Test func timedItemIsTimeThenTitle() {
        let line = WidgetRowText.lockLine(item(), calendar: Self.cal, locale: us)
        #expect(plain(line.time) == "9:00 AM")
        #expect(line.title == "Standup")
        #expect(plain(line.text) == "9:00 AM Standup")
    }

    @Test func allDayItemIsTitleOnly() {
        let line = WidgetRowText.lockLine(item("Trip", allDay: true), calendar: Self.cal, locale: us)
        #expect(line.time == nil)
        #expect(line.text == "Trip")
        let dateOnly = WidgetRowText.lockLine(item("Pay rent", allDay: true, reminder: true), calendar: Self.cal, locale: us)
        #expect(dateOnly.text == "Pay rent")
    }

    @Test func overdueItemIsTitleOnly() {
        let line = WidgetRowText.lockLine(item("Pay rent", reminder: true, overdue: true), calendar: Self.cal, locale: us)
        #expect(line.time == nil)
        #expect(line.text == "Pay rent")
    }

    @Test func tomorrowsItemsSaySo() {
        let timed = WidgetRowText.lockLine(item(tomorrow: true), calendar: Self.cal, locale: us)
        #expect(plain(timed.text) == "Tmrw 9:00 AM Standup")
        let allDay = WidgetRowText.lockLine(item("Trip", allDay: true, tomorrow: true), calendar: Self.cal, locale: us)
        #expect(allDay.text == "Tomorrow Trip")
    }

    @Test func emptyTitleReadsUntitled() {
        let line = WidgetRowText.lockLine(item(""), calendar: Self.cal, locale: us)
        #expect(line.title == "Untitled")
        #expect(plain(line.text) == "9:00 AM Untitled")
    }
}
