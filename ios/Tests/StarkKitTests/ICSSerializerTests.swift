// ios/Tests/StarkKitTests/ICSSerializerTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("ICSSerializer")
struct ICSSerializerTests {
    @Test("serializes a timed event with RRULE")
    func serializesEventWithRecurrence() {
        let event = Event(
            id: "evt-1",
            title: "Standup",
            start: DateMath.date(from: "2026-09-17"),
            recurrence: RecurrenceRule(frequency: .weekly, byDay: [.monday, .wednesday, .friday])
        )

        let text = ICSSerializer.serialize(event: event)

        #expect(text.contains("BEGIN:VEVENT"))
        #expect(text.contains("UID:evt-1"))
        #expect(text.contains("SUMMARY:Standup"))
        #expect(text.contains("RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR"))
        #expect(text.contains("END:VEVENT"))
    }

    @Test("serializes a completed reminder with priority")
    func serializesCompletedReminder() {
        let reminder = Reminder(
            id: "rem-1",
            title: "Call dentist",
            dueDate: DateMath.date(from: "2026-09-20"),
            isCompleted: true,
            completedDate: DateMath.date(from: "2026-09-19"),
            priority: 1
        )

        let text = ICSSerializer.serialize(reminder: reminder)

        #expect(text.contains("BEGIN:VTODO"))
        #expect(text.contains("PRIORITY:1"))
        #expect(text.contains("STATUS:COMPLETED"))
        #expect(text.contains("END:VTODO"))
    }

    @Test("escapes commas, semicolons, and newlines in free text")
    func escapesSpecialCharacters() {
        let event = Event(title: "Lunch; drinks, then home\nlate", start: Date())
        let text = ICSSerializer.serialize(event: event)
        #expect(text.contains("SUMMARY:Lunch\\; drinks\\, then home\\nlate"))
    }

    @Test("wraps multiple items in one VCALENDAR document")
    func wholeFileWrapsMultipleItems() {
        let event = Event(title: "Standup", start: Date())
        let reminder = Reminder(title: "Call dentist")
        let text = ICSSerializer.serialize(events: [event], reminders: [reminder])
        #expect(text.hasPrefix("BEGIN:VCALENDAR\r\n"))
        #expect(text.hasSuffix("END:VCALENDAR\r\n"))
        #expect(text.contains("BEGIN:VEVENT"))
        #expect(text.contains("BEGIN:VTODO"))
    }
}
