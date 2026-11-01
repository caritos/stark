// ios/Tests/StarkKitTests/PlannerStoreConversionTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("PlannerStore conversion (issue #116)")
struct PlannerStoreConversionTests {
    private let calendar = Calendar(identifier: .gregorian)

    @MainActor
    private func makeStore() -> (PlannerStore, PlannerFile, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = PlannerFile(directory: root.appendingPathComponent("docs"), pendingDirectory: root.appendingPathComponent("pending"))
        return (PlannerStore(file: file), file, root)
    }

    @MainActor
    private func start(_ store: PlannerStore, around date: Date) {
        let range = AgendaWindow.loadRange(around: date)
        store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
    }

    /// A fresh store over the same files, as on relaunch.
    @MainActor
    private func reloaded(_ file: PlannerFile, around date: Date) -> PlannerStore {
        let store = PlannerStore(file: file)
        start(store, around: date)
        return store
    }

    private func at(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: DateMath.date(from: day))!
    }

    private let nov = YearMonth(date: DateMath.date(from: "2026-11-02"))
    private let dec = YearMonth(date: DateMath.date(from: "2026-12-02"))

    // MARK: Event -> Reminder

    @Test("a one-off event becomes a reminder in its month file, same id, nothing duplicated")
    @MainActor
    func oneOffEventToReminder() throws {
        let (store, file, _) = makeStore()
        let day = DateMath.date(from: "2026-11-02")
        start(store, around: day)
        let event = Event(title: "Dentist", notes: "Card", start: at("2026-11-03", 14, 30), end: at("2026-11-03", 15),
                          location: "Main St", url: "https://d.example")
        let other = Event(title: "Keep", start: at("2026-11-04", 9))
        store.addEvent(event)
        store.addEvent(other)

        #expect(store.convertToReminder(eventID: event.id))

        #expect(store.events.map(\.id) == [other.id])
        #expect(store.reminders.map(\.id) == [event.id])
        let onDisk = try file.loadMonth(nov)
        #expect(onDisk.events.map(\.id) == [other.id])
        #expect(onDisk.reminders.count == 1)
        let reminder = try #require(onDisk.reminders.first)
        #expect(reminder.id == event.id)
        #expect(reminder.dueDate == at("2026-11-03", 14, 30))
        #expect(reminder.notes == "Card\n\nLocation: Main St\nURL: https://d.example")
        #expect(try file.loadRecurring().reminders.isEmpty)

        let again = reloaded(file, around: day)
        #expect(again.events.map(\.id) == [other.id])
        #expect(again.reminders.map(\.id) == [event.id])
    }

    @Test("a recurring event with marks becomes a recurring reminder in recurring.ics; marks dropped")
    @MainActor
    func recurringEventToReminder() throws {
        let (store, file, root) = makeStore()
        let day = DateMath.date(from: "2026-11-02")
        start(store, around: day)
        var rule = RecurrenceRule(frequency: .weekly)
        rule.until = calendar.startOfDay(for: DateMath.date(from: "2026-12-29"))
        let exdate = at("2026-11-10", 18)
        let event = Event(title: "Class", start: at("2026-11-03", 18), end: at("2026-11-03", 19),
                          location: "Hall", recurrence: rule, exceptionDates: [exdate])
        store.addEvent(event)
        store.setEventOutcome(id: event.id, on: at("2026-11-03", 18), outcome: .attended)
        #expect(store.events.first?.outcomes.count == 1)

        #expect(store.convertToReminder(eventID: event.id))

        let recurring = try file.loadRecurring()
        #expect(recurring.events.isEmpty)
        let reminder = try #require(recurring.reminders.first)
        #expect(recurring.reminders.count == 1)
        #expect(reminder.id == event.id)
        #expect(reminder.recurrence == rule)
        #expect(reminder.exceptionDates.count == 1)
        #expect(calendar.isDate(reminder.exceptionDates[0], inSameDayAs: exdate))
        #expect(reminder.notes == "Location: Hall")
        // Never written to a month file.
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/\(nov.fileName)").path))
        let text = try String(contentsOf: root.appendingPathComponent("docs/recurring.ics"), encoding: .utf8)
        #expect(!text.contains("X-STARK-ATTENDED"))

        let again = reloaded(file, around: day)
        #expect(again.events.isEmpty)
        #expect(again.reminders.map(\.id) == [event.id])
    }

    @Test("an edited value moves a one-off to the month its new due date is in")
    @MainActor
    func convertWithEditMovesMonth() throws {
        let (store, file, root) = makeStore()
        let day = DateMath.date(from: "2026-11-02")
        start(store, around: day)
        let event = Event(title: "Trip", start: at("2026-11-20", 9))
        store.addEvent(event)
        var edited = ItemConversion.reminder(from: event)
        edited.dueDate = at("2026-12-02", 9)
        edited.priority = 1
        edited.id = "ignored"

        #expect(store.convertEvent(id: event.id, to: edited))

        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/\(nov.fileName)").path))
        let december = try file.loadMonth(dec)
        #expect(december.reminders.map(\.id) == [event.id])  // the original id is kept
        #expect(december.reminders.first?.priority == 1)
        #expect(store.events.isEmpty)
    }

    @Test("an unreadable destination month aborts: nothing removed, nothing written")
    @MainActor
    func unreadableDestinationAborts() throws {
        let (store, file, root) = makeStore()
        let day = DateMath.date(from: "2026-11-02")
        // A directory where December's file should be: exists, but cannot be read as text.
        let decPath = root.appendingPathComponent("docs/\(dec.fileName)")
        try FileManager.default.createDirectory(at: decPath, withIntermediateDirectories: true)
        start(store, around: day)
        let event = Event(title: "Trip", start: at("2026-11-20", 9))
        store.addEvent(event)
        store.error = nil
        var edited = ItemConversion.reminder(from: event)
        edited.dueDate = at("2026-12-02", 9)

        #expect(!store.convertEvent(id: event.id, to: edited))

        #expect(store.error != nil)
        #expect(store.events.map(\.id) == [event.id])
        #expect(store.reminders.isEmpty)
        #expect(try file.loadMonth(nov).events.map(\.id) == [event.id])
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: decPath.path, isDirectory: &isDir) && isDir.boolValue)
    }

    @Test("an unknown id is a no-op returning false")
    @MainActor
    func unknownIDs() {
        let (store, _, _) = makeStore()
        start(store, around: DateMath.date(from: "2026-11-02"))
        #expect(!store.convertToReminder(eventID: "nope"))
        #expect(!store.convertToEvent(reminderID: "nope"))
        #expect(store.events.isEmpty && store.reminders.isEmpty)
    }

    // MARK: Reminder -> Event

    @Test("a one-off task becomes an event in its month file; priority dropped")
    @MainActor
    func oneOffReminderToEvent() throws {
        let (store, file, _) = makeStore()
        let day = DateMath.date(from: "2026-11-02")
        start(store, around: day)
        let reminder = Reminder(title: "Write", notes: "Draft", dueDate: at("2026-11-05", 14, 30), priority: 1)
        store.addReminder(reminder)

        #expect(store.convertToEvent(reminderID: reminder.id))

        let onDisk = try file.loadMonth(nov)
        #expect(onDisk.reminders.isEmpty)
        let event = try #require(onDisk.events.first)
        #expect(onDisk.events.count == 1)
        #expect(event.id == reminder.id)
        #expect(event.start == at("2026-11-05", 14, 30))
        #expect(event.end == nil)
        #expect(!event.isAllDay)
        #expect(event.notes == "Draft")

        let again = reloaded(file, around: day)
        #expect(again.reminders.isEmpty)
        #expect(again.events.map(\.id) == [reminder.id])
    }

    @Test("a recurring task becomes a recurring event; its completed copies stay as history")
    @MainActor
    func recurringReminderToEvent() throws {
        let (store, file, _) = makeStore()
        let day = DateMath.date(from: "2026-11-02")
        start(store, around: day)
        var rule = RecurrenceRule(frequency: .daily)
        rule.count = 30
        let reminder = Reminder(title: "Stretch", dueDate: calendar.startOfDay(for: DateMath.date(from: "2026-11-01")),
                                recurrence: rule)
        store.addReminder(reminder)
        store.completeReminder(id: reminder.id, on: calendar.startOfDay(for: DateMath.date(from: "2026-11-01")),
                               today: day, now: day)
        let copy = try #require(store.reminders.first { $0.seriesID == reminder.id })
        let masterExdates = try #require(store.reminders.first { $0.id == reminder.id }).exceptionDates
        #expect(!masterExdates.isEmpty)

        #expect(store.convertToEvent(reminderID: reminder.id))

        let recurring = try file.loadRecurring()
        #expect(recurring.reminders.isEmpty)
        let event = try #require(recurring.events.first)
        #expect(event.id == reminder.id)
        #expect(event.isAllDay)
        #expect(event.recurrence == rule)
        #expect(event.exceptionDates == masterExdates)
        // The completed copy is untouched in its month file.
        #expect(try file.loadMonth(nov).reminders == [copy])

        let again = reloaded(file, around: day)
        #expect(again.events.map(\.id) == [reminder.id])
        #expect(again.reminders.map(\.id) == [copy.id])
    }

    @Test("a completed task is not convertible: false, nothing changes")
    @MainActor
    func completedReminderNotConvertible() throws {
        let (store, file, _) = makeStore()
        let day = DateMath.date(from: "2026-11-02")
        start(store, around: day)
        let reminder = Reminder(title: "Done", dueDate: at("2026-11-02", 9))
        store.addReminder(reminder)
        store.completeReminder(id: reminder.id, on: at("2026-11-02", 9), today: day, now: day)
        let before = try file.loadMonth(nov)
        let beforeEvents = before.events, beforeReminders = before.reminders

        #expect(!store.convertToEvent(reminderID: reminder.id))
        #expect(!store.convertReminder(id: reminder.id, to: Event(title: "x", start: day)))

        #expect(store.events.isEmpty)
        #expect(store.reminders.map(\.id) == [reminder.id])
        let after = try file.loadMonth(nov)
        #expect(after.events == beforeEvents)
        #expect(after.reminders == beforeReminders)
    }

    @Test("a plan for a task converted to an event is a harmless orphan")
    @MainActor
    func planOrphanIsHarmless() throws {
        let (store, _, _) = makeStore()
        let day = DateMath.date(from: "2026-11-02")
        start(store, around: day)
        let reminder = Reminder(title: "Write", dueDate: at("2026-11-02", 14))
        store.addReminder(reminder)
        let block = PlanBlock(reminderID: reminder.id, occurrence: at("2026-11-02", 14), start: at("2026-11-02", 10), minutes: 30)
        store.replacePlans(on: day, with: [block])

        #expect(store.convertToEvent(reminderID: reminder.id))

        // The block is kept (not deleted) but matches nothing.
        #expect(store.plans == [block])
        let model = DayPlanModel.make(day: day, events: store.events, reminders: store.reminders,
                                      plans: store.plans, today: day)
        #expect(model.blocks.isEmpty)
        #expect(model.tray.isEmpty)
        #expect(model.events.map(\.id).count == 1)
        let range = AgendaWindow.range(around: day)
        let items = buildAgendaItems(events: store.events, reminders: store.reminders, in: range, today: day)
        let planned = applyPlans(items, plans: store.plans, today: day, reminders: store.reminders)
        #expect(planned.allSatisfy { $0.plan == nil })
        #expect(planned.count == items.count)
    }
}
