// ios/Tests/StarkKitTests/ItemConversionTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("ItemConversion (issue #116)")
struct ItemConversionTests {
    private let calendar = Calendar(identifier: .gregorian)

    /// Local date at the given time.
    private func at(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        let noon = DateMath.date(from: day)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: noon)!
    }

    private func startOfDay(_ day: String) -> Date {
        calendar.startOfDay(for: DateMath.date(from: day))
    }

    // MARK: Event -> Reminder

    @Test("a timed event keeps id, title, notes and start as the due time; the end is dropped")
    func timedEventToReminder() {
        let event = Event(id: "E1", title: "Dentist", notes: "Bring card",
                          start: at("2026-11-03", 14, 30), end: at("2026-11-03", 15, 30))
        let reminder = ItemConversion.reminder(from: event)
        #expect(reminder.id == "E1")
        #expect(reminder.title == "Dentist")
        #expect(reminder.notes == "Bring card")
        #expect(reminder.dueDate == at("2026-11-03", 14, 30))
        #expect(!FormFields.isAllDay(reminder))
        #expect(reminder.isCompleted == false)
        #expect(reminder.completedDate == nil)
        #expect(reminder.priority == nil)
        #expect(reminder.seriesID == nil)
    }

    @Test("an all-day event becomes an all-day reminder (due at the start of its day)")
    func allDayEventToReminder() {
        let event = Event(title: "Holiday", start: startOfDay("2026-11-03"),
                          end: startOfDay("2026-11-05"), isAllDay: true)
        let reminder = ItemConversion.reminder(from: event)
        #expect(reminder.dueDate == startOfDay("2026-11-03"))
        #expect(FormFields.isAllDay(reminder))
    }

    @Test("an all-day event stored off midnight is still due at the start of its day")
    func allDayEventOffMidnight() {
        let event = Event(title: "Holiday", start: at("2026-11-03", 12), isAllDay: true)
        #expect(ItemConversion.reminder(from: event).dueDate == startOfDay("2026-11-03"))
    }

    @Test("location and URL are appended to the notes after a blank line")
    func locationAndURLAppended() {
        let event = Event(title: "Gym", notes: "Leg day", start: at("2026-11-03", 7),
                          location: "Main St 1", url: "https://gym.example")
        #expect(ItemConversion.reminder(from: event).notes == "Leg day\n\nLocation: Main St 1\nURL: https://gym.example")
    }

    @Test("location only, with no notes, becomes the whole notes (no leading blank line)")
    func locationOnlyNoNotes() {
        let event = Event(title: "Gym", start: at("2026-11-03", 7), location: "Main St 1")
        #expect(ItemConversion.reminder(from: event).notes == "Location: Main St 1")
    }

    @Test("URL only is appended")
    func urlOnly() {
        let event = Event(title: "Call", notes: "Agenda", start: at("2026-11-03", 7), url: "https://meet.example/x")
        #expect(ItemConversion.reminder(from: event).notes == "Agenda\n\nURL: https://meet.example/x")
    }

    @Test("neither location nor URL leaves the notes as they were, nil included")
    func neitherLocationNorURL() {
        let withNotes = Event(title: "A", notes: "Keep", start: at("2026-11-03", 7))
        let without = Event(title: "B", start: at("2026-11-03", 7))
        #expect(ItemConversion.reminder(from: withNotes).notes == "Keep")
        #expect(ItemConversion.reminder(from: without).notes == nil)
    }

    @Test("blank location / URL / notes are skipped, and values are trimmed")
    func blankValuesSkipped() {
        let event = Event(title: "A", notes: "  \n ", start: at("2026-11-03", 7),
                          location: "   ", url: "  https://x.example  ")
        #expect(ItemConversion.reminder(from: event).notes == "URL: https://x.example")
    }

    @Test("a recurring event keeps its rule (until and count) and exception dates")
    func recurringEventToReminder() {
        let until = startOfDay("2026-12-31")
        var rule = RecurrenceRule(frequency: .weekly)
        rule.until = until
        let exdates = [at("2026-11-10", 18), at("2026-11-17", 18)]
        let event = Event(title: "Class", start: at("2026-11-03", 18), end: at("2026-11-03", 19),
                          recurrence: rule, exceptionDates: exdates)
        let reminder = ItemConversion.reminder(from: event)
        #expect(reminder.recurrence == rule)
        #expect(reminder.recurrence?.until == until)
        #expect(reminder.exceptionDates == exdates)

        var counted = RecurrenceRule(frequency: .daily, interval: 2)
        counted.count = 10
        let countedEvent = Event(title: "Run", start: at("2026-11-03", 6), recurrence: counted)
        #expect(ItemConversion.reminder(from: countedEvent).recurrence == counted)
    }

    @Test("attended/skipped marks cannot be kept; droppedMarks counts them")
    func marksDropped() {
        let event = Event(title: "Class", start: at("2026-11-03", 18), recurrence: RecurrenceRule(frequency: .weekly),
                          outcomes: [EventOutcomeRecord(date: at("2026-11-03", 18), outcome: .attended),
                                     EventOutcomeRecord(date: at("2026-11-10", 18), outcome: .skipped)])
        #expect(ItemConversion.droppedMarks(converting: event) == 2)
        #expect(ItemConversion.droppedMarks(converting: Event(title: "x", start: at("2026-11-03", 1))) == 0)
        // A converted reminder has no attendance concept; converting back has no marks either.
        let back = ItemConversion.event(from: ItemConversion.reminder(from: event), undatedStart: Date())
        #expect(back.outcomes.isEmpty)
    }

    // MARK: Reminder -> Event

    @Test("a task due at 14:30 becomes a timed event with no end")
    func timedReminderToEvent() {
        let reminder = Reminder(id: "R1", title: "Write", notes: "Draft", dueDate: at("2026-11-03", 14, 30), priority: 1)
        let event = ItemConversion.event(from: reminder, undatedStart: Date())
        #expect(event.id == "R1")
        #expect(event.title == "Write")
        #expect(event.notes == "Draft")
        #expect(event.start == at("2026-11-03", 14, 30))
        #expect(event.end == nil)
        #expect(event.isAllDay == false)
        #expect(event.location == nil)
        #expect(event.url == nil)
        #expect(event.outcomes.isEmpty)
    }

    @Test("a no-time (start-of-day) task becomes an all-day event")
    func dateOnlyReminderToEvent() {
        let reminder = Reminder(title: "Taxes", dueDate: startOfDay("2026-11-03"))
        let event = ItemConversion.event(from: reminder, undatedStart: Date())
        #expect(event.isAllDay)
        #expect(event.start == startOfDay("2026-11-03"))
        #expect(event.end == nil)
    }

    @Test("an undated task becomes an all-day event on the fallback day")
    func undatedReminderToEvent() {
        let reminder = Reminder(title: "Someday")
        let event = ItemConversion.event(from: reminder, undatedStart: at("2026-11-04", 9, 15))
        #expect(event.isAllDay)
        #expect(event.start == startOfDay("2026-11-04"))
    }

    @Test("priority is dropped (events never carry one); recurrence and exception dates carry over")
    func recurringReminderToEvent() {
        var rule = RecurrenceRule(frequency: .monthly)
        rule.count = 6
        let exdates = [at("2026-12-03", 8)]
        let reminder = Reminder(title: "Rent", dueDate: at("2026-11-03", 8), priority: 5,
                                recurrence: rule, exceptionDates: exdates)
        let event = ItemConversion.event(from: reminder, undatedStart: Date())
        #expect(event.recurrence == rule)
        #expect(event.exceptionDates == exdates)
        // Event has no priority field at all; converting back gives none.
        #expect(ItemConversion.reminder(from: event).priority == nil)
    }

    @Test("isConvertible: only open reminders")
    func onlyOpenRemindersConvertible() {
        #expect(ItemConversion.isConvertible(Reminder(title: "Open", dueDate: at("2026-11-03", 8))))
        #expect(!ItemConversion.isConvertible(Reminder(title: "Done", dueDate: at("2026-11-03", 8),
                                                        isCompleted: true, completedDate: at("2026-11-03", 8))))
    }
}
