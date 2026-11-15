// ios/Tests/StarkKitTests/ReminderAlarmShiftTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("ReminderAlarmShift")
struct ReminderAlarmShiftTests {
    private let due = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour = 3600.0
    private let day = 86_400.0

    /// A fixed zone with DST, so the day-shift cases do not depend on the machine's zone.
    private var newYork: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func ny(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func shiftedTimed(_ alerts: [Date], oldDue: Date?, newDue: Date?) -> [Date?] {
        ReminderAlarmShift.shifted(alerts, oldDue: oldDue, oldHasTime: true, newDue: newDue, newHasTime: true,
                                   calendar: newYork)
    }

    @Test("timed to timed: every absolute alert moves by the plain difference, either way")
    func shiftsByTheDelta() {
        let alerts = [due, due.addingTimeInterval(-hour)]
        #expect(shiftedTimed(alerts, oldDue: due, newDue: due.addingTimeInterval(2 * day))
                == [due.addingTimeInterval(2 * day), due.addingTimeInterval(2 * day - hour)])
        #expect(shiftedTimed(alerts, oldDue: due, newDue: due.addingTimeInterval(-day))
                == [due.addingTimeInterval(-day), due.addingTimeInterval(-day - hour)])
    }

    @Test("an unchanged due date, no alerts, or no old due date leave the alerts as they are")
    func unchanged() {
        let alerts = [due.addingTimeInterval(-hour)]
        #expect(shiftedTimed(alerts, oldDue: due, newDue: due) == [due.addingTimeInterval(-hour)])
        #expect(shiftedTimed([], oldDue: due, newDue: due.addingTimeInterval(day)).isEmpty)
        #expect(shiftedTimed(alerts, oldDue: nil, newDue: due) == [due.addingTimeInterval(-hour)])
        let midnight = ny(2026, 11, 20)
        #expect(ReminderAlarmShift.shifted([ny(2026, 11, 20, 9)], oldDue: midnight, oldHasTime: false,
                                           newDue: midnight, newHasTime: false, calendar: newYork)
                == [ny(2026, 11, 20, 9)])
    }

    @Test("clearing the due date drops the alert at the old due time and keeps the others")
    func clearedDueDropsTheDueAlert() {
        let other = due.addingTimeInterval(-hour)
        #expect(shiftedTimed([due, other], oldDue: due, newDue: nil) == [nil, other])
    }

    @Test("timed to date-only on a later day: a 09:00 alert stays at 09:00 on the new day")
    func timedToDateOnlyKeepsTimeOfDay() {
        let shifted = ReminderAlarmShift.shifted([ny(2026, 11, 20, 9)], oldDue: ny(2026, 11, 20, 9), oldHasTime: true,
                                                 newDue: ny(2026, 11, 22), newHasTime: false, calendar: newYork)
        #expect(shifted == [ny(2026, 11, 22, 9)])
        // Same day, time switched off: the alert does not move to midnight.
        #expect(ReminderAlarmShift.shifted([ny(2026, 11, 20, 9)], oldDue: ny(2026, 11, 20, 9), oldHasTime: true,
                                           newDue: ny(2026, 11, 20), newHasTime: false, calendar: newYork)
                == [ny(2026, 11, 20, 9)])
    }

    @Test("date-only to timed: the alert keeps its time of day, on the new due's day")
    func dateOnlyToTimedKeepsTimeOfDay() {
        #expect(ReminderAlarmShift.shifted([ny(2026, 11, 20, 9)], oldDue: ny(2026, 11, 20), oldHasTime: false,
                                           newDue: ny(2026, 11, 20, 14), newHasTime: true, calendar: newYork)
                == [ny(2026, 11, 20, 9)])
        #expect(ReminderAlarmShift.shifted([ny(2026, 11, 20, 9)], oldDue: ny(2026, 11, 20), oldHasTime: false,
                                           newDue: ny(2026, 11, 23, 14), newHasTime: true, calendar: newYork)
                == [ny(2026, 11, 23, 9)])
    }

    @Test("date-only to date-only across a DST change: the alert keeps its time of day")
    func dateOnlyAcrossDST() {
        // US DST ends on 2026-11-01: a 23-hour plain difference would land at 08:00.
        #expect(ReminderAlarmShift.shifted([ny(2026, 10, 31, 9)], oldDue: ny(2026, 10, 31), oldHasTime: false,
                                           newDue: ny(2026, 11, 2), newHasTime: false, calendar: newYork)
                == [ny(2026, 11, 2, 9)])
    }
}
