import Testing
import Foundation
@testable import StarkKit

@Suite("Models")
struct ModelsTests {
    @Test("Event defaults to no recurrence, no exceptions, not all-day")
    func eventDefaults() {
        let event = Event(title: "Standup", start: Date())
        #expect(event.recurrence == nil)
        #expect(event.exceptionDates.isEmpty)
        #expect(event.isAllDay == false)
    }

    @Test("Reminder defaults to incomplete with no priority")
    func reminderDefaults() {
        let reminder = Reminder(title: "Call dentist")
        #expect(reminder.isCompleted == false)
        #expect(reminder.completedDate == nil)
        #expect(reminder.priority == nil)
    }

    // MARK: Event.settingStart

    private func date(_ iso: String, hour: Int, minute: Int = 0) -> Date {
        let base = DateMath.date(from: iso)
        return Calendar(identifier: .gregorian).date(bySettingHour: hour, minute: minute, second: 0, of: base)!
    }

    @Test("settingStart with no end just moves start and leaves end nil")
    func settingStartWithoutEnd() {
        let event = Event(title: "Standup", start: date("2026-09-20", hour: 9))
        let moved = event.settingStart(date("2026-09-22", hour: 10))
        #expect(moved.start == date("2026-09-22", hour: 10))
        #expect(moved.end == nil)
    }

    @Test("settingStart shifts end by the same delta so duration is preserved")
    func settingStartPreservesDuration() {
        let event = Event(title: "Dentist", start: date("2026-10-23", hour: 14, minute: 30), end: date("2026-10-23", hour: 15, minute: 30))
        let moved = event.settingStart(date("2026-10-23", hour: 16))
        #expect(moved.start == date("2026-10-23", hour: 16))
        #expect(moved.end == date("2026-10-23", hour: 17))
        #expect(moved.end!.timeIntervalSince(moved.start) == 3600)
    }

    @Test("settingStart to an earlier day moves end back with it")
    func settingStartEarlierDay() {
        let event = Event(title: "Trip", start: date("2026-10-23", hour: 9), end: date("2026-10-25", hour: 18))
        let moved = event.settingStart(date("2026-10-20", hour: 9))
        #expect(moved.start == date("2026-10-20", hour: 9))
        #expect(moved.end == date("2026-10-22", hour: 18))
    }

    @Test("settingStart to a later day moves end forward with it")
    func settingStartLaterDay() {
        let event = Event(title: "Trip", start: date("2026-10-23", hour: 9), end: date("2026-10-23", hour: 11))
        let moved = event.settingStart(date("2026-11-02", hour: 9))
        #expect(moved.start == date("2026-11-02", hour: 9))
        #expect(moved.end == date("2026-11-02", hour: 11))
    }

    @Test("settingStart leaves every other field untouched")
    func settingStartLeavesOtherFields() {
        let rule = RecurrenceRule(frequency: .weekly)
        let exdate = date("2026-10-30", hour: 9)
        let event = Event(
            id: "fixed-id",
            title: "Class",
            notes: "Bring laptop",
            start: date("2026-10-23", hour: 9),
            end: date("2026-10-23", hour: 10),
            isAllDay: true,
            location: "Room 4",
            recurrence: rule,
            exceptionDates: [exdate]
        )
        let moved = event.settingStart(date("2026-10-24", hour: 9))
        var expected = event
        expected.start = date("2026-10-24", hour: 9)
        expected.end = date("2026-10-24", hour: 10)
        #expect(moved == expected)
    }

    @Test("settingStart to the same start is a no-op")
    func settingStartSameStart() {
        let event = Event(title: "Same", start: date("2026-10-23", hour: 9), end: date("2026-10-23", hour: 10))
        #expect(event.settingStart(event.start) == event)
    }
}
