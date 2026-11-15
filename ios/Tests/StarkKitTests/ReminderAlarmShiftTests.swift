// ios/Tests/StarkKitTests/ReminderAlarmShiftTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("ReminderAlarmShift")
struct ReminderAlarmShiftTests {
    private let due = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour = 3600.0
    private let day = 86_400.0

    @Test("moving the due date moves every absolute alert by the same amount, either way")
    func shiftsByTheDelta() {
        let alerts = [due, due.addingTimeInterval(-hour)]
        #expect(ReminderAlarmShift.shifted(alerts, oldDue: due, newDue: due.addingTimeInterval(2 * day))
                == [due.addingTimeInterval(2 * day), due.addingTimeInterval(2 * day - hour)])
        #expect(ReminderAlarmShift.shifted(alerts, oldDue: due, newDue: due.addingTimeInterval(-day))
                == [due.addingTimeInterval(-day), due.addingTimeInterval(-day - hour)])
    }

    @Test("an unchanged due date, no alerts, or no old due date leave the alerts as they are")
    func unchanged() {
        let alerts = [due.addingTimeInterval(-hour)]
        #expect(ReminderAlarmShift.shifted(alerts, oldDue: due, newDue: due) == [due.addingTimeInterval(-hour)])
        #expect(ReminderAlarmShift.shifted([], oldDue: due, newDue: due.addingTimeInterval(day)).isEmpty)
        #expect(ReminderAlarmShift.shifted(alerts, oldDue: nil, newDue: due) == [due.addingTimeInterval(-hour)])
    }

    @Test("clearing the due date drops the alert at the old due time and keeps the others")
    func clearedDueDropsTheDueAlert() {
        let other = due.addingTimeInterval(-hour)
        #expect(ReminderAlarmShift.shifted([due, other], oldDue: due, newDue: nil) == [nil, other])
    }
}
