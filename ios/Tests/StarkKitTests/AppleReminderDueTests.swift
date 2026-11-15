import Foundation
import Testing
@testable import StarkKit

/// `appleReminderDue` turns EventKit's `dueDateComponents` (Gregorian field values) into a date.
/// It must never resolve them with the phone's own calendar: (2026, 11, 15) read with the
/// Buddhist calendar is the Gregorian year 1483, with the Japanese calendar 4044.
@Suite("AppleReminderDue")
struct AppleReminderDueTests {
    private let ny = TimeZone(identifier: "America/New_York")!

    private func gregorian(_ tz: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }

    private func expected(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, tz: TimeZone) -> Date {
        gregorian(tz).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test(arguments: [Calendar.Identifier.buddhist, .japanese, .gregorian])
    func gregorianFieldsResolveTheSameWhateverTheDeviceCalendar(_ id: Calendar.Identifier) {
        // What EventKit can hand over on a phone set to a non-Gregorian calendar: Gregorian field
        // values, with (or without) that calendar attached.
        var deviceCalendar = Calendar(identifier: id)
        deviceCalendar.timeZone = ny
        var comps = DateComponents(year: 2026, month: 11, day: 15)
        comps.calendar = deviceCalendar
        comps.timeZone = ny
        let due = appleReminderDue(comps)
        #expect(due.date == expected(2026, 11, 15, tz: ny))
        #expect(!due.hasTime)
    }

    @Test func buddhistCalendarWouldMisreadTheYear() {
        // Documents the bug: the device calendar reads 2026 as a Buddhist-era year.
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = ny
        let wrong = buddhist.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        #expect(gregorian(ny).component(.year, from: wrong) == 1483)
    }

    @Test func withHourAndMinuteHasTime() {
        var comps = DateComponents(year: 2026, month: 11, day: 15, hour: 14, minute: 30)
        comps.timeZone = ny
        let due = appleReminderDue(comps)
        #expect(due.date == expected(2026, 11, 15, 14, 30, tz: ny))
        #expect(due.hasTime)
    }

    @Test func dateOnlyIsLocalMidnightWithoutTime() {
        var comps = DateComponents(year: 2026, month: 3, day: 1)
        comps.timeZone = ny
        let due = appleReminderDue(comps)
        #expect(due.date == expected(2026, 3, 1, tz: ny))
        #expect(!due.hasTime)
    }

    @Test func dstSpringForwardDayKeepsWallClockTime() {
        // 2026-03-08 is the US spring-forward day (02:00 -> 03:00).
        var comps = DateComponents(year: 2026, month: 3, day: 8, hour: 9, minute: 0)
        comps.timeZone = ny
        let due = appleReminderDue(comps)
        let date = try! #require(due.date)
        let back = gregorian(ny).dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(back.year == 2026 && back.month == 3 && back.day == 8 && back.hour == 9 && back.minute == 0)
        #expect(due.hasTime)
    }

    @Test func nilTimeZoneUsesTheFallbackZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let comps = DateComponents(year: 2026, month: 11, day: 15, hour: 8)
        let due = appleReminderDue(comps, fallbackTimeZone: tokyo)
        #expect(due.date == expected(2026, 11, 15, 8, tz: tokyo))
    }

    @Test func componentsTimeZoneWinsOverFallback() {
        var comps = DateComponents(year: 2026, month: 11, day: 15, hour: 8)
        comps.timeZone = ny
        let due = appleReminderDue(comps, fallbackTimeZone: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(due.date == expected(2026, 11, 15, 8, tz: ny))
    }

    @Test func missingDayGivesNoDate() {
        let due = appleReminderDue(DateComponents(year: 2026, month: 11))
        #expect(due.date == nil)
        #expect(!due.hasTime)
    }
}
