// ios/Tests/StarkKitTests/ItemEditFormTests.swift
import Testing
import Foundation
@testable import StarkKit

/// The edit sheet's form (moved from `EditItemView`) and the baseline that keeps an Apple edit's
/// patch to the fields the owner actually changed (spec call 5).
@Suite("ItemEditForm")
struct ItemEditFormTests {
    private let cal = Calendar(identifier: .gregorian)

    private func local(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func details(event: Event) -> ItemDetails {
        ItemDetails(event: event, calendarID: "cal")
    }

    private func details(reminder: Reminder, dueHasTime: Bool, url: String? = nil) -> ItemDetails {
        ItemDetails(reminder: reminder, dueHasTime: dueHasTime, reminderURL: url, calendarID: "list")
    }

    // MARK: Untouched form = empty patch

    @Test("an untouched all-day single-day Apple event (end = its own day) gives an empty patch")
    func allDaySingleDayUntouched() {
        let stored = Event(id: "apple-E", title: "Holiday", start: local(16), end: local(16), isAllDay: true)
        let form = ItemEditForm(event: stored)
        #expect(EventPatch(from: details(event: stored).formBaseline(), to: form.edited(stored)) == EventPatch())
        // Against the raw stored item the same save would clear the end: the trap this avoids.
        #expect(EventPatch(from: details(event: stored), to: form.edited(stored)) != EventPatch())
    }

    @Test("untrimmed notes and location from Calendar are not rewritten by an untouched form")
    func untrimmedTextUntouched() {
        let stored = Event(id: "apple-E", title: "Lunch", notes: "bring cash\n", start: local(16, 12),
                           end: local(16, 13), location: " Cafe ")
        let form = ItemEditForm(event: stored)
        #expect(EventPatch(from: details(event: stored).formBaseline(), to: form.edited(stored)) == EventPatch())
    }

    @Test("a repeating event with an until date round-trips through the form unchanged")
    func repeatWithUntilUntouched() {
        let rule = RecurrenceRule(frequency: .weekly, until: local(30))
        let stored = Event(id: "apple-E", title: "Gym", start: local(16, 7), end: local(16, 8), recurrence: rule)
        let form = ItemEditForm(event: stored)
        #expect(EventPatch(from: details(event: stored).formBaseline(), to: form.edited(stored)) == EventPatch())
    }

    @Test("a title-only edit of a repeating event patches only the title")
    func titleOnlyEdit() {
        let stored = Event(id: "apple-E", title: "Gym", notes: "x ", start: local(16, 7), end: local(16, 8),
                           recurrence: RecurrenceRule(frequency: .daily))
        var form = ItemEditForm(event: stored)
        form.title = "Gym class"
        #expect(EventPatch(from: details(event: stored).formBaseline(), to: form.edited(stored))
            == EventPatch(title: "Gym class"))
    }

    @Test("moving a series' time of day patches start and end only, keeping the series' first date")
    func timeOfDayEdit() {
        let stored = Event(id: "apple-E", title: "Gym", start: local(10, 7), end: local(10, 8),
                           recurrence: RecurrenceRule(frequency: .daily))
        var form = ItemEditForm(event: stored)
        let newStart = local(10, 9)
        form.endDate = EventSchedule.shiftedEnd(form.endDate, oldStart: form.date, newStart: newStart)
        form.date = newStart
        let patch = EventPatch(from: details(event: stored).formBaseline(), to: form.edited(stored))
        #expect(patch == EventPatch(start: local(10, 9), end: .set(local(10, 10))))
    }

    @Test("untouched date-only and timed reminders give an empty patch; the URL is kept")
    func remindersUntouched() {
        let dateOnly = Reminder(id: "apple-R", title: "Milk", notes: "2 l\n", dueDate: local(16), priority: 5)
        let timed = Reminder(id: "apple-T", title: "Call", dueDate: local(16, 15, 30),
                             recurrence: RecurrenceRule(frequency: .weekly, count: 4))
        for (reminder, hasTime) in [(dateOnly, false), (timed, true)] {
            let stored = details(reminder: reminder, dueHasTime: hasTime, url: "https://example.com")
            let form = ItemEditForm(reminder: reminder, occurrence: local(16))
            #expect(ReminderPatch(from: stored.formBaseline(), to: form.edited(reminder), url: stored.reminderURL)
                == ReminderPatch())
        }
    }

    @Test("an undated reminder stays undated through an untouched form")
    func undatedReminderUntouched() {
        let reminder = Reminder(id: "apple-U", title: "Someday")
        let stored = details(reminder: reminder, dueHasTime: true)
        let form = ItemEditForm(reminder: reminder, occurrence: local(16, 12))
        #expect(form.edited(reminder).dueDate == nil)
        #expect(ReminderPatch(from: stored.formBaseline(), to: form.edited(reminder), url: nil) == ReminderPatch())
    }

    // MARK: The moved form keeps the old view's behaviour

    @Test("the form applies its fields like the old EditItemView did")
    func formAppliesFields() {
        let event = Event(id: "e1", title: "Lunch", start: local(16, 12), end: local(16, 13))
        var form = ItemEditForm(event: event)
        form.title = "  Dinner "
        form.notes = " "
        form.location = " Home "
        form.recurrence = RecurrenceRule(frequency: .daily)
        form.repeatEnd = .afterCount(3)
        let edited = form.edited(event)
        #expect(edited.title == "Dinner")
        #expect(edited.notes == nil)
        #expect(edited.location == "Home")
        #expect(edited.recurrence == RecurrenceRule(frequency: .daily, count: 3))
        #expect(edited.id == "e1")

        let reminder = Reminder(id: "r1", title: "Milk", priority: 1)
        var reminderForm = ItemEditForm(reminder: reminder, occurrence: local(16, 12))
        reminderForm.allDay = true
        let editedReminder = reminderForm.edited(reminder)
        #expect(editedReminder.dueDate == local(16))
        #expect(editedReminder.priority == 1)
    }

    @Test("the row's form starts from the row: title, occurrence for an undated reminder")
    func formFromRow() {
        let reminder = Reminder(id: "r1", title: "Milk")
        let item = AgendaItem(kind: .reminder(reminder), occurrence: local(16, 12), displayDate: local(16, 12),
                              isOverdue: false)
        let form = ItemEditForm(item: item)
        #expect(form.title == "Milk")
        #expect(form.date == local(16, 12))
        #expect(form.initialDate == local(16, 12))
        #expect(form.allDay == false)
    }
}
