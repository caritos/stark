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

    @Test("a literal backslash immediately followed by the letter n round-trips exactly, distinct from an escaped newline")
    func literalBackslashNRoundTrips() {
        // The Swift string literal "a\\nb" is four characters: a, \, n, b — a literal
        // backslash followed by the letter n, NOT a newline.
        let original = Event(
            id: "evt-2",
            title: "a\\nb",
            start: DateMath.date(from: "2026-09-17")
        )

        let text = ICSSerializer.serialize(events: [original], reminders: [])
        let result = ICSParser.parse(text)

        #expect(result.events.count == 1)
        #expect(result.events[0].title == "a\\nb")
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

    // MARK: - Event outcomes

    @Test("marks survive serialize -> parse -> serialize byte for byte, timed and all-day")
    func outcomesRoundTrip() {
        let timed = Event(
            id: "evt-1",
            title: "Class",
            start: DateMath.date(from: "2026-09-20"),
            recurrence: RecurrenceRule(frequency: .weekly),
            exceptionDates: [DateMath.date(from: "2026-10-04")],
            outcomes: [
                EventOutcomeRecord(date: DateMath.date(from: "2026-09-20"), outcome: .attended),
                EventOutcomeRecord(date: DateMath.date(from: "2026-09-27"), outcome: .skipped),
            ]
        )
        let allDay = Event(
            id: "evt-2",
            title: "Trip",
            start: DateMath.date(from: "2026-09-21"),
            isAllDay: true,
            outcomes: [EventOutcomeRecord(date: DateMath.date(from: "2026-09-21"), outcome: .skipped)]
        )
        let text = ICSSerializer.serialize(events: [timed, allDay], reminders: [])

        let parsed = ICSParser.parse(text)

        #expect(parsed.events.count == 2)
        #expect(parsed.events[0].outcomes == timed.outcomes)
        #expect(parsed.events[1].outcomes.map(\.outcome) == [.skipped])
        #expect(ICSSerializer.serialize(events: parsed.events, reminders: parsed.reminders) == text)
    }

    @Test("unparseable dates and unknown X-STARK outcome names are ignored")
    func garbledOutcomesIgnored() {
        let text = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "BEGIN:VEVENT",
            "UID:evt-1",
            "SUMMARY:Class",
            "DTSTART:20260920T120000",
            "X-STARK-ATTENDED:notadate",
            "X-STARK-MAYBE:20260920T120000",
            "X-STARK-SKIPPED:20260921T120000",
            "END:VEVENT",
            "END:VCALENDAR",
            "",
        ].joined(separator: "\r\n")

        let parsed = ICSParser.parse(text)

        #expect(parsed.events.count == 1)
        #expect(parsed.events[0].outcomes.map(\.outcome) == [.skipped])
    }
}
