// ios/Tests/StarkKitTests/EventRescheduleTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("Event.rescheduled")
struct EventRescheduleTests {
    private let cal = Calendar(identifier: .gregorian)

    private func at(_ iso: String, _ hour: Int, _ minute: Int = 0) -> Date {
        let c = DateMath.components(iso)
        return cal.date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: hour, minute: minute))!
    }

    @Test("a timed event made all-day starts at midnight and drops its end")
    func timedToAllDay() {
        let event = Event(id: "e", title: "Class", start: at("2026-09-20", 9), end: at("2026-09-20", 10))

        let result = event.rescheduled(to: at("2026-09-20", 15), allDay: true)

        #expect(result.isAllDay)
        #expect(result.start == cal.startOfDay(for: at("2026-09-20", 15)))
        #expect(result.end == nil)
    }

    @Test("an all-day event made timed takes the chosen time and has no end")
    func allDayToTimed() {
        let event = Event(id: "e", title: "Trip", start: cal.startOfDay(for: at("2026-09-20", 12)), isAllDay: true)

        let result = event.rescheduled(to: at("2026-09-20", 14, 30), allDay: false)

        #expect(!result.isAllDay)
        #expect(result.start == at("2026-09-20", 14, 30))
        #expect(result.end == nil)
    }

    @Test("a timed event that stays timed keeps its duration when moved")
    func timedStaysTimed() {
        let event = Event(id: "e", title: "Class", start: at("2026-09-20", 9), end: at("2026-09-20", 10))

        let result = event.rescheduled(to: at("2026-09-21", 11), allDay: false)

        #expect(result.start == at("2026-09-21", 11))
        #expect(result.end == at("2026-09-21", 12))
        #expect(!result.isAllDay)
    }

    @Test("an all-day multi-day event that stays all-day keeps its end, shifted by the same days")
    func allDayStaysAllDay() {
        let start = cal.startOfDay(for: at("2026-09-20", 12))
        let end = cal.startOfDay(for: at("2026-09-22", 12))
        let event = Event(id: "e", title: "Trip", start: start, end: end, isAllDay: true)

        let result = event.rescheduled(to: cal.startOfDay(for: at("2026-09-21", 12)), allDay: true)

        #expect(result.isAllDay)
        #expect(result.start == cal.startOfDay(for: at("2026-09-21", 12)))
        #expect(result.end == cal.startOfDay(for: at("2026-09-23", 12)))
    }

    @Test("every other field is preserved")
    func otherFieldsPreserved() {
        let event = Event(
            id: "e", title: "Class", notes: "n", start: at("2026-09-20", 9), location: "Room 4",
            recurrence: RecurrenceRule(frequency: .weekly),
            exceptionDates: [at("2026-09-27", 9)],
            outcomes: [EventOutcomeRecord(date: at("2026-09-20", 9), outcome: .attended)]
        )

        let result = event.rescheduled(to: at("2026-09-20", 9), allDay: true)

        #expect(result.id == "e")
        #expect(result.title == "Class")
        #expect(result.notes == "n")
        #expect(result.location == "Room 4")
        #expect(result.recurrence == event.recurrence)
        #expect(result.exceptionDates == event.exceptionDates)
        #expect(result.outcomes == event.outcomes)
    }
}
