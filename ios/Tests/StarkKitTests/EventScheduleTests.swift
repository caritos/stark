// ios/Tests/StarkKitTests/EventScheduleTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("EventSchedule")
struct EventScheduleTests {
    private let cal = Calendar(identifier: .gregorian)

    private func at(_ iso: String, _ hour: Int, _ minute: Int = 0) -> Date {
        let c = DateMath.components(iso)
        return cal.date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: hour, minute: minute))!
    }

    @Test("a new event defaults to one hour")
    func defaultDuration() {
        #expect(EventSchedule.defaultDuration == 3600)
    }

    @Test("moving the start moves the end by the same amount")
    func shiftedEnd() {
        let end = EventSchedule.shiftedEnd(at("2026-09-20", 15), oldStart: at("2026-09-20", 14), newStart: at("2026-09-21", 9))
        #expect(end == at("2026-09-21", 10))
    }

    @Test("an end is stored only when strictly after the start")
    func storedEnd() {
        let start = at("2026-09-20", 14)
        #expect(EventSchedule.storedEnd(at("2026-09-20", 15), start: start) == at("2026-09-20", 15))
        #expect(EventSchedule.storedEnd(start, start: start) == nil)
        #expect(EventSchedule.storedEnd(at("2026-09-20", 13), start: start) == nil)
    }

    @Test("a timed schedule takes the given start and end exactly and clears all-day")
    func timedSchedule() {
        let event = Event(id: "e", title: "Class", start: cal.startOfDay(for: at("2026-09-20", 12)), isAllDay: true)

        let result = event.scheduled(start: at("2026-09-21", 14), end: at("2026-09-21", 15), allDay: false)

        #expect(!result.isAllDay)
        #expect(result.start == at("2026-09-21", 14))
        #expect(result.end == at("2026-09-21", 15))
    }

    @Test("a timed schedule with no end clears the end")
    func timedScheduleWithoutEnd() {
        let event = Event(id: "e", title: "Class", start: at("2026-09-20", 9), end: at("2026-09-20", 10))

        let result = event.scheduled(start: at("2026-09-20", 9), end: nil, allDay: false)

        #expect(result.end == nil)
    }

    @Test("an all-day schedule follows rescheduled(to:allDay:): drops a timed end, keeps an all-day one")
    func allDaySchedule() {
        let timed = Event(id: "e", title: "Class", start: at("2026-09-20", 9), end: at("2026-09-20", 10))
        let toAllDay = timed.scheduled(start: at("2026-09-20", 9), end: at("2026-09-20", 10), allDay: true)
        #expect(toAllDay.isAllDay)
        #expect(toAllDay.end == nil)

        let start = cal.startOfDay(for: at("2026-09-20", 12))
        let end = cal.startOfDay(for: at("2026-09-22", 12))
        let multiDay = Event(id: "t", title: "Trip", start: start, end: end, isAllDay: true)
        let moved = multiDay.scheduled(start: cal.startOfDay(for: at("2026-09-21", 12)), end: nil, allDay: true)
        #expect(moved.isAllDay)
        #expect(moved.end == cal.startOfDay(for: at("2026-09-23", 12)))
    }

    @Test("every other field is preserved")
    func otherFieldsPreserved() {
        let event = Event(
            id: "e", title: "Class", notes: "n", start: at("2026-09-20", 9), location: "Room 4",
            recurrence: RecurrenceRule(frequency: .weekly),
            exceptionDates: [at("2026-09-27", 9)],
            outcomes: [EventOutcomeRecord(date: at("2026-09-20", 9), outcome: .attended)]
        )

        let result = event.scheduled(start: at("2026-09-20", 10), end: at("2026-09-20", 11), allDay: false)

        #expect(result.id == "e")
        #expect(result.title == "Class")
        #expect(result.notes == "n")
        #expect(result.location == "Room 4")
        #expect(result.recurrence == event.recurrence)
        #expect(result.exceptionDates == event.exceptionDates)
        #expect(result.outcomes == event.outcomes)
    }

    @Test("scheduling keeps the URL")
    func keepsURL() {
        let event = Event(id: "e", title: "Call", start: at("2026-09-20", 9), url: "https://example.com")

        #expect(event.scheduled(start: at("2026-09-20", 10), end: at("2026-09-20", 11), allDay: false).url == "https://example.com")
        #expect(event.scheduled(start: at("2026-09-20", 10), end: nil, allDay: true).url == "https://example.com")
    }
}
