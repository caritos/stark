// ios/Tests/StarkKitTests/ICSParserTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("ICSParser")
struct ICSParserTests {
    @Test("round-trips an event with recurrence through serialize/parse")
    func roundTripsEvent() {
        let original = Event(
            id: "evt-1",
            title: "Standup",
            start: DateMath.date(from: "2026-09-17"),
            recurrence: RecurrenceRule(frequency: .weekly, byDay: [.monday, .wednesday, .friday]),
            exceptionDates: [DateMath.date(from: "2026-09-23")]
        )

        let text = ICSSerializer.serialize(events: [original], reminders: [])
        let result = ICSParser.parse(text)

        #expect(result.events.count == 1)
        #expect(result.events[0].id == "evt-1")
        #expect(result.events[0].title == "Standup")
        #expect(result.events[0].recurrence == original.recurrence)
        #expect(result.events[0].exceptionDates.count == 1)
        #expect(result.warnings.isEmpty)
    }

    @Test("round-trips a completed reminder with priority")
    func roundTripsReminder() {
        let original = Reminder(
            id: "rem-1",
            title: "Call dentist",
            dueDate: DateMath.date(from: "2026-09-20"),
            isCompleted: true,
            completedDate: DateMath.date(from: "2026-09-19"),
            priority: 1
        )

        let text = ICSSerializer.serialize(events: [], reminders: [original])
        let result = ICSParser.parse(text)

        #expect(result.reminders.count == 1)
        #expect(result.reminders[0].isCompleted == true)
        #expect(result.reminders[0].priority == 1)
    }

    @Test("skips a malformed block and still parses its valid siblings")
    func skipsMalformedBlock() {
        let text = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VTODO
        UID:bad-1
        END:VTODO
        BEGIN:VTODO
        UID:good-1
        SUMMARY:Buy milk
        STATUS:NEEDS-ACTION
        END:VTODO
        END:VCALENDAR
        """

        let result = ICSParser.parse(text)

        #expect(result.reminders.count == 1)
        #expect(result.reminders[0].id == "good-1")
        #expect(result.warnings.count == 1)
    }
}
