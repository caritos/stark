// ios/Tests/StarkKitTests/AppleEventEndTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("appleEventEnd")
struct AppleEventEndTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    @Test func timedEndPassesThrough() {
        let end = date(2026, 11, 16, 0, 0)
        #expect(appleEventEnd(start: date(2026, 11, 15, 22), end: end, isAllDay: false, calendar: calendar) == end)
    }

    @Test func nilEndStaysNil() {
        #expect(appleEventEnd(start: date(2026, 11, 15), end: nil, isAllDay: true, calendar: calendar) == nil)
    }

    @Test func allDayEndAtLastSecondIsThatDay() {
        // EventKit's usual all-day end: 23:59:59 on the last day.
        let end = appleEventEnd(start: date(2026, 11, 15), end: date(2026, 11, 15, 23, 59, 59),
                                isAllDay: true, calendar: calendar)
        #expect(end == date(2026, 11, 15))
    }

    @Test func allDayEndAtNextMidnightIsInclusiveLastDay() {
        let end = appleEventEnd(start: date(2026, 11, 15), end: date(2026, 11, 17),
                                isAllDay: true, calendar: calendar)
        #expect(end == date(2026, 11, 16))
    }

    @Test func allDaySingleDayWithEndEqualStartStaysOnStartDay() {
        let end = appleEventEnd(start: date(2026, 11, 15), end: date(2026, 11, 15),
                                isAllDay: true, calendar: calendar)
        #expect(end == date(2026, 11, 15))
    }

    @Test func allDayAcrossDSTEndKeepsLastDay() {
        // DST ends 2026-11-01 in New York.
        let end = appleEventEnd(start: date(2026, 10, 31), end: date(2026, 11, 2),
                                isAllDay: true, calendar: calendar)
        #expect(end == date(2026, 11, 1))
    }

    @Test func mergedAllDayEventFromNextMidnightEndHasNoExtraRow() {
        let cal = AppleCalendarInfo(id: "c", title: "C", accountName: "iCloud", colorHex: nil, isReminderList: false)
        let start = date(2026, 11, 15)
        let event = AppleCalendarEvent(id: "e", title: "Trip", notes: nil, location: nil, url: nil, start: start,
                                       end: appleEventEnd(start: start, end: date(2026, 11, 17), isAllDay: true,
                                                          calendar: calendar),
                                       isAllDay: true, calendar: cal)
        let items = mergeAppleItems([], snapshot: AppleSnapshot(events: [event], reminders: []),
                                    in: date(2026, 11, 1)...date(2026, 11, 30), today: start, calendar: calendar)
        let days: [Date] = items.map { $0.displayDate }
        #expect(days == [date(2026, 11, 15), date(2026, 11, 16)])
    }
}
