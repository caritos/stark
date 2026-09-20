// ios/Tests/StarkKitTests/FormRoundTripTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("opening and saving unchanged is a no-op")
struct FormRoundTripTests {
    private let cal = Calendar(identifier: .gregorian)

    private var noon: Date { DateMath.date(from: "2026-09-20") }
    private var midnight: Date { cal.startOfDay(for: noon) }
    private var laterMidnight: Date { cal.startOfDay(for: DateMath.date(from: "2026-09-22")) }

    /// Mirrors `EditItemView.save()` for an event the user opened and saved without touching:
    /// the form is seeded (`EventSchedule.formEnd`, `Event.isAllDay`) and then saved through
    /// `scheduled(start:end:allDay:)` with `EventSchedule.storedEnd`. Must be kept in sync with
    /// the view's save.
    private func savedUnchanged(_ event: Event) -> Event {
        let date = event.start
        let endDate = EventSchedule.formEnd(for: event)
        let allDay = event.isAllDay
        var updated = event.scheduled(start: date, end: EventSchedule.storedEnd(endDate, start: date), allDay: allDay)
        updated.title = event.title
        updated.recurrence = event.recurrence
        updated.notes = FormFields.trimmedOrNil(event.notes ?? "")
        updated.location = FormFields.trimmedOrNil(event.location ?? "")
        return updated
    }

    /// Mirrors `EditItemView.save()` for a reminder the user opened and saved without touching
    /// (the due date and priority parts). Must be kept in sync with the view's save.
    private func savedUnchanged(_ reminder: Reminder) -> Reminder {
        var updated = reminder
        let date = reminder.dueDate!
        let allDay = FormFields.isAllDay(reminder)
        updated.dueDate = FormFields.normalizedStart(date, allDay: allDay)
        updated.priority = ReminderPriority.updated(
            original: reminder.priority,
            chosen: ReminderPriority(icalValue: reminder.priority)
        )
        return updated
    }

    // MARK: Events

    @Test("a timed event with an end round-trips")
    func timedEventWithEnd() {
        let event = Event(title: "Lunch", notes: "bring cash", start: noon, end: noon.addingTimeInterval(5400),
                          location: "Cafe")
        #expect(savedUnchanged(event) == event)
    }

    @Test("a timed event without an end round-trips and stays without one")
    func timedEventWithoutEnd() {
        let event = Event(title: "Call", start: noon)
        #expect(savedUnchanged(event) == event)
    }

    @Test("an all-day event without an end round-trips")
    func allDayEventWithoutEnd() {
        let event = Event(title: "Holiday", start: midnight, isAllDay: true)
        #expect(savedUnchanged(event) == event)
    }

    @Test("an all-day event with an end round-trips")
    func allDayEventWithEnd() {
        let event = Event(title: "Trip", start: midnight, end: laterMidnight, isAllDay: true)
        #expect(savedUnchanged(event) == event)
    }

    // MARK: Reminders

    @Test("a timed reminder round-trips")
    func timedReminder() {
        let reminder = Reminder(title: "Pay rent", dueDate: noon)
        #expect(savedUnchanged(reminder).dueDate == reminder.dueDate)
        #expect(savedUnchanged(reminder).priority == reminder.priority)
        #expect(savedUnchanged(reminder) == reminder)
    }

    @Test("a date-only reminder round-trips")
    func dateOnlyReminder() {
        let reminder = Reminder(title: "Renew passport", dueDate: midnight)
        #expect(savedUnchanged(reminder).dueDate == midnight)
        #expect(savedUnchanged(reminder) == reminder)
    }

    @Test("a reminder with an imported priority keeps it")
    func importedPriority() {
        let reminder = Reminder(title: "Imported", dueDate: noon, priority: 3)
        #expect(savedUnchanged(reminder).priority == 3)
        #expect(savedUnchanged(reminder) == reminder)
    }

    @Test("a reminder with no priority stays without one")
    func nilPriority() {
        let reminder = Reminder(title: "Plain", dueDate: noon, priority: nil)
        #expect(savedUnchanged(reminder).priority == nil)
        #expect(savedUnchanged(reminder) == reminder)
    }

    // MARK: The seeding helpers themselves

    @Test("formEnd: an event's own end for a timed event, else Starts")
    func formEnd() {
        let end = noon.addingTimeInterval(3600)
        #expect(EventSchedule.formEnd(for: Event(title: "a", start: noon, end: end)) == end)
        #expect(EventSchedule.formEnd(for: Event(title: "b", start: noon)) == noon)
        #expect(EventSchedule.formEnd(for: Event(title: "c", start: midnight, end: laterMidnight, isAllDay: true)) == midnight)
    }

    @Test("isAllDay(reminder): false when undated or timed, true when date-only")
    func reminderIsAllDay() {
        #expect(!FormFields.isAllDay(Reminder(title: "undated")))
        #expect(!FormFields.isAllDay(Reminder(title: "timed", dueDate: noon)))
        #expect(FormFields.isAllDay(Reminder(title: "date-only", dueDate: midnight)))
    }
}
