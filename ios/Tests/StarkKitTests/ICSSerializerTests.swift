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

    // MARK: - Event outcomes

    @Test("serializes attended and skipped marks after EXDATE, in order, byte for byte")
    func serializesEventOutcomes() {
        let event = Event(
            id: "evt-1",
            title: "Class",
            start: DateMath.date(from: "2026-09-20"),
            exceptionDates: [DateMath.date(from: "2026-10-04")],
            outcomes: [
                EventOutcomeRecord(date: DateMath.date(from: "2026-09-20"), outcome: .attended),
                EventOutcomeRecord(date: DateMath.date(from: "2026-09-27"), outcome: .skipped),
            ]
        )

        let text = ICSSerializer.serialize(event: event)

        #expect(text == [
            "BEGIN:VEVENT",
            "UID:evt-1",
            "SUMMARY:Class",
            "DTSTART:20260920T120000",
            "EXDATE:20261004T120000",
            "X-STARK-ATTENDED:20260920T120000",
            "X-STARK-SKIPPED:20260927T120000",
            "END:VEVENT",
        ].joined(separator: "\r\n"))
    }

    @Test("an all-day event's marks use VALUE=DATE like its EXDATE lines")
    func serializesAllDayEventOutcome() {
        let event = Event(
            id: "evt-2",
            title: "Trip",
            start: DateMath.date(from: "2026-09-21"),
            isAllDay: true,
            outcomes: [EventOutcomeRecord(date: DateMath.date(from: "2026-09-21"), outcome: .skipped)]
        )

        let text = ICSSerializer.serialize(event: event)

        #expect(text.contains("X-STARK-SKIPPED;VALUE=DATE:20260921"))
    }

    @Test("an event with no marks writes no X-STARK lines")
    func noOutcomesNoLines() {
        let text = ICSSerializer.serialize(event: Event(id: "evt-3", title: "Plain", start: DateMath.date(from: "2026-09-20")))
        #expect(!text.contains("X-STARK"))
    }
}
