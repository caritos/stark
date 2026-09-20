// ios/Tests/StarkKitTests/PlannerStoreTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("PlannerStore")
struct PlannerStoreTests {
    @MainActor
    private func makeStore() -> (PlannerStore, PlannerFile, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = PlannerFile(directory: root.appendingPathComponent("docs"), pendingDirectory: root.appendingPathComponent("pending"))
        return (PlannerStore(file: file), file, root)
    }

    /// Starts the store with the same load window the real app uses, so tests can't
    /// drift from it the way the original ± 1 month bug did.
    @MainActor
    private func start(_ store: PlannerStore, around date: Date) {
        let range = AgendaWindow.loadRange(around: date)
        store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
    }

    @Test("a non-recurring event is written to its own month's file")
    @MainActor
    func nonRecurringEventGoesToMonthFile() throws {
        let (store, file, _) = makeStore()
        start(store, around: DateMath.date(from: "2026-09-01"))

        store.addEvent(Event(title: "Standup", start: DateMath.date(from: "2026-09-17")))

        let onDisk = try file.loadMonth(YearMonth(year: 2026, month0: 8))
        #expect(onDisk.events.map(\.title) == ["Standup"])
        #expect(store.events.map(\.title) == ["Standup"])
    }

    @Test("a recurring reminder is written to recurring.ics, not a month file")
    @MainActor
    func recurringReminderGoesToRecurringFile() throws {
        let (store, file, _) = makeStore()
        start(store, around: DateMath.date(from: "2026-09-01"))

        store.addReminder(Reminder(
            title: "Take out trash",
            dueDate: DateMath.date(from: "2026-09-17"),
            recurrence: RecurrenceRule(frequency: .weekly)
        ))

        let recurring = try file.loadRecurring()
        #expect(recurring.reminders.map(\.title) == ["Take out trash"])
        let month = try file.loadMonth(YearMonth(year: 2026, month0: 8))
        #expect(month.reminders.isEmpty)
    }

    @Test("completing one occurrence of a recurring reminder exdates the master and logs a completion")
    @MainActor
    func completingRecurringReminderExdatesAndLogs() throws {
        let (store, file, _) = makeStore()
        start(store, around: DateMath.date(from: "2026-09-01"))
        store.addReminder(Reminder(
            id: "rem-1",
            title: "Take out trash",
            dueDate: DateMath.date(from: "2026-09-17"),
            recurrence: RecurrenceRule(frequency: .weekly)
        ))

        store.completeReminder(id: "rem-1", on: DateMath.date(from: "2026-09-17"))

        let recurring = try file.loadRecurring()
        #expect(recurring.reminders.first?.exceptionDates.count == 1)
        let month = try file.loadMonth(YearMonth(year: 2026, month0: 8))
        #expect(month.reminders.contains { $0.isCompleted && $0.title == "Take out trash" })
    }

    // MARK: - Fix 1: agenda window and loaded months must match

    @Test("start loads every month covered by the agenda window, not just center ± 1")
    @MainActor
    func startLoadsFullAgendaWindow() {
        // Starting on the 20th pushes the +60-day window end into a month more than one
        // away from center (Sept 20 center → window end Nov 19). The old `center ± 1`
        // loading (Aug/Sep/Oct) never touched November, so an item there would be lost
        // the next time the store loaded fresh (i.e. on relaunch).
        let (store, file, _) = makeStore()
        let anchor = DateMath.date(from: "2026-09-20")
        start(store, around: anchor)

        store.addEvent(Event(title: "Far Out", start: DateMath.date(from: "2026-11-09")))
        #expect(store.events.map(\.title).contains("Far Out"))

        // Simulate a relaunch: a brand-new store reading from the same files on disk.
        let relaunchedStore = PlannerStore(file: file)
        start(relaunchedStore, around: anchor)

        #expect(relaunchedStore.events.map(\.title).contains("Far Out"))
    }

    // MARK: - Fix 2: pending writes are retried, and errors are observable

    @Test("start retries pending writes so a previously failed save becomes visible")
    @MainActor
    func startRetriesPendingWrites() throws {
        let (store, file, root) = makeStore()
        let anchor = DateMath.date(from: "2026-09-01")

        // Simulate a write that failed in a previous session: content queued in the
        // pending directory, but never landing in the real one.
        let pendingDir = root.appendingPathComponent("pending")
        try FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        let recovered = Event(title: "Recovered", start: DateMath.date(from: "2026-09-17"))
        let content = ICSSerializer.serialize(events: [recovered], reminders: [])
        try content.write(
            to: pendingDir.appendingPathComponent(YearMonth(year: 2026, month0: 8).fileName),
            atomically: true,
            encoding: .utf8
        )
        #expect(file.pendingWriteCount == 1)

        start(store, around: anchor)

        #expect(file.pendingWriteCount == 0)
        #expect(store.events.map(\.title).contains("Recovered"))
    }

    // MARK: - Fix 3: a genuine read failure must never be treated as empty truth

    @Test("a genuine read failure (corrupt encoding) is surfaced as an error, not silently treated as empty")
    @MainActor
    func genuineReadFailureIsSurfacedNotSwallowed() throws {
        let (store, _, root) = makeStore()
        let docsDir = root.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        // A real file that exists but can't be decoded as UTF-8 text — a genuine read
        // failure, distinct from "the file doesn't exist yet".
        let corruptBytes = Data([0xFF, 0xFE, 0x00])
        try corruptBytes.write(to: docsDir.appendingPathComponent("recurring.ics"))

        start(store, around: DateMath.date(from: "2026-09-01"))

        #expect(store.error != nil)
        // The corrupt file must not have been silently overwritten with an empty calendar
        // just because the in-memory "truth" after the failed read looked empty.
        let onDisk = try Data(contentsOf: docsDir.appendingPathComponent("recurring.ics"))
        #expect(onDisk == corruptBytes)
    }

    @Test("deleting a month-only event does not rewrite recurring.ics")
    @MainActor
    func monthOnlyEventDeleteDoesNotTouchRecurringFile() {
        let (store, _, root) = makeStore()
        start(store, around: DateMath.date(from: "2026-09-01"))
        let recurringURL = root.appendingPathComponent("docs").appendingPathComponent("recurring.ics")

        store.addEvent(Event(id: "evt-1", title: "Standup", start: DateMath.date(from: "2026-09-17")))
        #expect(!FileManager.default.fileExists(atPath: recurringURL.path))

        store.deleteEvent(id: "evt-1")

        #expect(!FileManager.default.fileExists(atPath: recurringURL.path))
    }

    @Test("deleting a month-only reminder does not rewrite recurring.ics")
    @MainActor
    func monthOnlyReminderDeleteDoesNotTouchRecurringFile() {
        let (store, _, root) = makeStore()
        start(store, around: DateMath.date(from: "2026-09-01"))
        let recurringURL = root.appendingPathComponent("docs").appendingPathComponent("recurring.ics")

        store.addReminder(Reminder(id: "rem-1", title: "Buy milk", dueDate: DateMath.date(from: "2026-09-17")))
        #expect(!FileManager.default.fileExists(atPath: recurringURL.path))

        store.deleteReminder(id: "rem-1")

        #expect(!FileManager.default.fileExists(atPath: recurringURL.path))
    }

    // MARK: - update APIs

    private static let anchor = DateMath.date(from: "2026-09-20")

    private func docsURL(_ root: URL, _ name: String) -> URL {
        root.appendingPathComponent("docs").appendingPathComponent(name)
    }

    private let sept = YearMonth(year: 2026, month0: 8)
    private let oct = YearMonth(year: 2026, month0: 9)

    @Test("updateEvent keeps the id, changes the title in place, and rewrites only that month file")
    @MainActor
    func updateEventSameMonth() throws {
        let (store, file, root) = makeStore()
        start(store, around: Self.anchor)
        store.addEvent(Event(id: "evt-1", title: "Standup", start: DateMath.date(from: "2026-09-17")))
        store.addEvent(Event(id: "evt-rec", title: "Weekly", start: DateMath.date(from: "2026-09-01"), recurrence: RecurrenceRule(frequency: .weekly)))
        // If update wrongly rewrote recurring.ics it would reappear.
        try FileManager.default.removeItem(at: docsURL(root, "recurring.ics"))

        var edited = try #require(store.events.first { $0.id == "evt-1" })
        edited.title = "Standup (moved to Zoom)"
        store.updateEvent(edited)

        #expect(store.events.filter { $0.id == "evt-1" }.map(\.title) == ["Standup (moved to Zoom)"])
        #expect(store.events.count == 2)
        let onDisk = try file.loadMonth(sept)
        #expect(onDisk.events.map(\.id) == ["evt-1"])
        #expect(onDisk.events.map(\.title) == ["Standup (moved to Zoom)"])
        #expect(!FileManager.default.fileExists(atPath: docsURL(root, "recurring.ics").path))
        #expect(store.error == nil)
    }

    @Test("updateEvent moves an event to a different month's file when its date changes month")
    @MainActor
    func updateEventMovesMonth() throws {
        let (store, file, _) = makeStore()
        start(store, around: Self.anchor)
        store.addEvent(Event(id: "evt-1", title: "Standup", start: DateMath.date(from: "2026-09-17")))

        var edited = try #require(store.events.first { $0.id == "evt-1" })
        edited.start = DateMath.date(from: "2026-10-05")
        store.updateEvent(edited)

        #expect(try file.loadMonth(sept).events.isEmpty)
        #expect(try file.loadMonth(oct).events.map(\.id) == ["evt-1"])
        let reloaded = PlannerStore(file: file)
        start(reloaded, around: Self.anchor)
        #expect(reloaded.events.map(\.id) == ["evt-1"])
        #expect(reloaded.events.first?.start == DateMath.date(from: "2026-10-05"))
    }

    @Test("updateEvent moves a one-off event into recurring.ics when a recurrence is added")
    @MainActor
    func updateEventOneOffToRecurring() throws {
        let (store, file, _) = makeStore()
        start(store, around: Self.anchor)
        store.addEvent(Event(id: "evt-1", title: "Standup", start: DateMath.date(from: "2026-09-17")))

        var edited = try #require(store.events.first { $0.id == "evt-1" })
        edited.recurrence = RecurrenceRule(frequency: .weekly)
        store.updateEvent(edited)

        #expect(try file.loadMonth(sept).events.isEmpty)
        #expect(try file.loadRecurring().events.map(\.id) == ["evt-1"])
        #expect(store.events.filter { $0.id == "evt-1" }.count == 1)
    }

    @Test("updateEvent moves a recurring event into its month file when the recurrence is removed")
    @MainActor
    func updateEventRecurringToOneOff() throws {
        let (store, file, _) = makeStore()
        start(store, around: Self.anchor)
        store.addEvent(Event(id: "evt-1", title: "Standup", start: DateMath.date(from: "2026-09-17"), recurrence: RecurrenceRule(frequency: .weekly)))

        var edited = try #require(store.events.first { $0.id == "evt-1" })
        edited.recurrence = nil
        store.updateEvent(edited)

        #expect(try file.loadRecurring().events.isEmpty)
        #expect(try file.loadMonth(sept).events.map(\.id) == ["evt-1"])
        #expect(store.events.filter { $0.id == "evt-1" }.count == 1)
    }

    @Test("updateEvent with an unknown id is a no-op and sets no error")
    @MainActor
    func updateEventUnknownIdIsNoOp() {
        let (store, _, root) = makeStore()
        start(store, around: Self.anchor)

        store.updateEvent(Event(id: "nope", title: "Ghost", start: DateMath.date(from: "2026-09-17")))

        #expect(store.events.isEmpty)
        #expect(store.error == nil)
        #expect(!FileManager.default.fileExists(atPath: docsURL(root, sept.fileName).path))
        #expect(!FileManager.default.fileExists(atPath: docsURL(root, "recurring.ics").path))
    }

    @Test("updateReminder keeps the id, changes the title in place, and rewrites only that month file")
    @MainActor
    func updateReminderSameMonth() throws {
        let (store, file, root) = makeStore()
        start(store, around: Self.anchor)
        store.addReminder(Reminder(id: "rem-1", title: "Buy milk", dueDate: DateMath.date(from: "2026-09-17")))
        store.addReminder(Reminder(id: "rem-rec", title: "Trash", dueDate: DateMath.date(from: "2026-09-01"), recurrence: RecurrenceRule(frequency: .weekly)))
        try FileManager.default.removeItem(at: docsURL(root, "recurring.ics"))

        var edited = try #require(store.reminders.first { $0.id == "rem-1" })
        edited.title = "Buy oat milk"
        store.updateReminder(edited)

        #expect(store.reminders.filter { $0.id == "rem-1" }.map(\.title) == ["Buy oat milk"])
        #expect(store.reminders.count == 2)
        let onDisk = try file.loadMonth(sept)
        #expect(onDisk.reminders.map(\.id) == ["rem-1"])
        #expect(onDisk.reminders.map(\.title) == ["Buy oat milk"])
        #expect(!FileManager.default.fileExists(atPath: docsURL(root, "recurring.ics").path))
        #expect(store.error == nil)
    }

    @Test("updateReminder moves a reminder to a different month's file when its due date changes month")
    @MainActor
    func updateReminderMovesMonth() throws {
        let (store, file, _) = makeStore()
        start(store, around: Self.anchor)
        store.addReminder(Reminder(id: "rem-1", title: "Buy milk", dueDate: DateMath.date(from: "2026-09-17")))

        var edited = try #require(store.reminders.first { $0.id == "rem-1" })
        edited.dueDate = DateMath.date(from: "2026-10-05")
        store.updateReminder(edited)

        #expect(try file.loadMonth(sept).reminders.isEmpty)
        #expect(try file.loadMonth(oct).reminders.map(\.id) == ["rem-1"])
        let reloaded = PlannerStore(file: file)
        start(reloaded, around: Self.anchor)
        #expect(reloaded.reminders.map(\.id) == ["rem-1"])
        #expect(reloaded.reminders.first?.dueDate == DateMath.date(from: "2026-10-05"))
    }

    @Test("updateReminder moves a one-off reminder into recurring.ics when a recurrence is added")
    @MainActor
    func updateReminderOneOffToRecurring() throws {
        let (store, file, _) = makeStore()
        start(store, around: Self.anchor)
        store.addReminder(Reminder(id: "rem-1", title: "Buy milk", dueDate: DateMath.date(from: "2026-09-17")))

        var edited = try #require(store.reminders.first { $0.id == "rem-1" })
        edited.recurrence = RecurrenceRule(frequency: .weekly)
        store.updateReminder(edited)

        #expect(try file.loadMonth(sept).reminders.isEmpty)
        #expect(try file.loadRecurring().reminders.map(\.id) == ["rem-1"])
        #expect(store.reminders.filter { $0.id == "rem-1" }.count == 1)
    }

    @Test("updateReminder moves a recurring reminder into its month file when the recurrence is removed")
    @MainActor
    func updateReminderRecurringToOneOff() throws {
        let (store, file, _) = makeStore()
        start(store, around: Self.anchor)
        store.addReminder(Reminder(id: "rem-1", title: "Buy milk", dueDate: DateMath.date(from: "2026-09-17"), recurrence: RecurrenceRule(frequency: .weekly)))

        var edited = try #require(store.reminders.first { $0.id == "rem-1" })
        edited.recurrence = nil
        store.updateReminder(edited)

        #expect(try file.loadRecurring().reminders.isEmpty)
        #expect(try file.loadMonth(sept).reminders.map(\.id) == ["rem-1"])
        #expect(store.reminders.filter { $0.id == "rem-1" }.count == 1)
    }

    @Test("updateReminder with an unknown id is a no-op and sets no error")
    @MainActor
    func updateReminderUnknownIdIsNoOp() {
        let (store, _, root) = makeStore()
        start(store, around: Self.anchor)

        store.updateReminder(Reminder(id: "nope", title: "Ghost", dueDate: DateMath.date(from: "2026-09-17")))

        #expect(store.reminders.isEmpty)
        #expect(store.error == nil)
        #expect(!FileManager.default.fileExists(atPath: docsURL(root, sept.fileName).path))
        #expect(!FileManager.default.fileExists(atPath: docsURL(root, "recurring.ics").path))
    }

    // MARK: - uncompleteReminder

    @Test("uncompleteReminder reopens a completed one-off reminder and persists across reload")
    @MainActor
    func uncompleteOneOffReminder() throws {
        let (store, file, _) = makeStore()
        start(store, around: Self.anchor)
        store.addReminder(Reminder(id: "rem-1", title: "Buy milk", dueDate: DateMath.date(from: "2026-09-17")))
        store.completeReminder(id: "rem-1", on: DateMath.date(from: "2026-09-17"))
        #expect(store.reminders.first { $0.id == "rem-1" }?.isCompleted == true)

        store.uncompleteReminder(id: "rem-1")

        let live = try #require(store.reminders.first { $0.id == "rem-1" })
        #expect(!live.isCompleted)
        #expect(live.completedDate == nil)
        let reloaded = PlannerStore(file: file)
        start(reloaded, around: Self.anchor)
        let persisted = try #require(reloaded.reminders.first { $0.id == "rem-1" })
        #expect(!persisted.isCompleted)
        #expect(persisted.completedDate == nil)
        #expect(reloaded.reminders.count == 1)
    }

    @Test("uncompleting the completed copy of a recurring occurrence leaves the master's exception alone and creates no duplicate")
    @MainActor
    func uncompleteCompletedCopyOfRecurringOccurrence() throws {
        let (store, file, _) = makeStore()
        let day = DateMath.date(from: "2026-09-17")
        start(store, around: Self.anchor)
        store.addReminder(Reminder(id: "rem-rec", title: "Trash", dueDate: day, recurrence: RecurrenceRule(frequency: .weekly)))
        store.completeReminder(id: "rem-rec", on: day)
        let copy = try #require(store.reminders.first { $0.isCompleted })
        #expect(copy.id != "rem-rec")

        store.uncompleteReminder(id: copy.id)

        let reopened = try #require(store.reminders.first { $0.id == copy.id })
        #expect(!reopened.isCompleted)
        #expect(reopened.completedDate == nil)
        #expect(reopened.recurrence == nil)

        let reloaded = PlannerStore(file: file)
        start(reloaded, around: Self.anchor)
        let calendar = Calendar(identifier: .gregorian)
        let master = try #require(reloaded.reminders.first { $0.id == "rem-rec" })
        #expect(master.exceptionDates.count == 1)
        #expect(reloaded.reminders.count == 2)
        // Exactly one open reminder lands on that date: the reopened one-off. The master's
        // exception date still suppresses its own occurrence there.
        let openOneOffsOnDay = reloaded.reminders.filter {
            !$0.isCompleted && $0.recurrence == nil && $0.dueDate.map { calendar.isDate($0, inSameDayAs: day) } == true
        }
        #expect(openOneOffsOnDay.map(\.id) == [copy.id])
        #expect(OccurrenceExpander.expand(reminder: master, in: day...DateMath.date(from: "2026-09-17")).isEmpty)
        #expect(reloaded.reminders.filter(\.isCompleted).isEmpty)
    }

    @Test("uncompleteReminder is a no-op for an unknown id, a recurring master, or an open reminder")
    @MainActor
    func uncompleteReminderNoOps() throws {
        let (store, _, root) = makeStore()
        start(store, around: Self.anchor)
        store.uncompleteReminder(id: "nope")
        #expect(store.reminders.isEmpty)
        #expect(store.error == nil)
        #expect(!FileManager.default.fileExists(atPath: docsURL(root, sept.fileName).path))

        store.addReminder(Reminder(id: "rem-open", title: "Buy milk", dueDate: DateMath.date(from: "2026-09-17")))
        store.addReminder(Reminder(id: "rem-rec", title: "Trash", dueDate: DateMath.date(from: "2026-09-10"), recurrence: RecurrenceRule(frequency: .weekly)))
        let before = store.reminders
        // Delete both files so any rewrite by a no-op call would be visible as a reappearance.
        try FileManager.default.removeItem(at: docsURL(root, sept.fileName))
        try FileManager.default.removeItem(at: docsURL(root, "recurring.ics"))

        store.uncompleteReminder(id: "rem-open")
        store.uncompleteReminder(id: "rem-rec")

        #expect(store.reminders == before)
        // Neither no-op rewrote a file.
        #expect(!FileManager.default.fileExists(atPath: docsURL(root, sept.fileName).path))
        #expect(!FileManager.default.fileExists(atPath: docsURL(root, "recurring.ics").path))
    }

    // MARK: - skipEvent / skipReminder

    private var septRange: ClosedRange<Date> {
        DateMath.date(from: "2026-09-01")...DateMath.date(from: "2026-09-30")
    }

    private func isoDays(_ dates: [Date]) -> [String] {
        dates.map { DateMath.isoDate(from: $0) }
    }

    @Test("skipEvent removes exactly that occurrence, keeps its neighbors, and persists across reload")
    @MainActor
    func skipEventRemovesOneOccurrence() throws {
        let (store, file, _) = makeStore()
        start(store, around: Self.anchor)
        store.addEvent(Event(id: "evt-rec", title: "Weekly", start: DateMath.date(from: "2026-09-03"), recurrence: RecurrenceRule(frequency: .weekly)))
        let all = OccurrenceExpander.expand(event: try #require(store.events.first), in: septRange)
        #expect(isoDays(all) == ["2026-09-03", "2026-09-10", "2026-09-17", "2026-09-24"])

        store.skipEvent(id: "evt-rec", on: DateMath.date(from: "2026-09-17"))

        let live = try #require(store.events.first { $0.id == "evt-rec" })
        #expect(isoDays(OccurrenceExpander.expand(event: live, in: septRange)) == ["2026-09-03", "2026-09-10", "2026-09-24"])
        let reloaded = PlannerStore(file: file)
        start(reloaded, around: Self.anchor)
        let persisted = try #require(reloaded.events.first { $0.id == "evt-rec" })
        #expect(isoDays(OccurrenceExpander.expand(event: persisted, in: septRange)) == ["2026-09-03", "2026-09-10", "2026-09-24"])
    }

    @Test("skipReminder removes exactly that occurrence, persists, and creates no completed reminder")
    @MainActor
    func skipReminderRemovesOneOccurrence() throws {
        let (store, file, _) = makeStore()
        start(store, around: Self.anchor)
        store.addReminder(Reminder(id: "rem-rec", title: "Trash", dueDate: DateMath.date(from: "2026-09-03"), recurrence: RecurrenceRule(frequency: .weekly)))

        // A fixed `today` before the skipped date, so this is a plain future skip that must not
        // clear anything earlier (and never depends on the real clock).
        store.skipReminder(id: "rem-rec", on: DateMath.date(from: "2026-09-17"), today: DateMath.date(from: "2026-09-01"))

        let live = try #require(store.reminders.first { $0.id == "rem-rec" })
        #expect(isoDays(OccurrenceExpander.expand(reminder: live, in: septRange)) == ["2026-09-03", "2026-09-10", "2026-09-24"])
        #expect(store.reminders.count == 1)
        #expect(store.reminders.filter(\.isCompleted).isEmpty)

        let reloaded = PlannerStore(file: file)
        start(reloaded, around: Self.anchor)
        let persisted = try #require(reloaded.reminders.first { $0.id == "rem-rec" })
        #expect(isoDays(OccurrenceExpander.expand(reminder: persisted, in: septRange)) == ["2026-09-03", "2026-09-10", "2026-09-24"])
        #expect(reloaded.reminders.count == 1)
        #expect(try file.loadMonth(sept).reminders.isEmpty)
    }

    @Test("skipping the same calendar day twice adds only one exception")
    @MainActor
    func skipSameDayTwiceAddsOneException() throws {
        let (store, _, _) = makeStore()
        start(store, around: Self.anchor)
        store.addEvent(Event(id: "evt-rec", title: "Weekly", start: DateMath.date(from: "2026-09-03"), recurrence: RecurrenceRule(frequency: .weekly)))
        store.addReminder(Reminder(id: "rem-rec", title: "Trash", dueDate: DateMath.date(from: "2026-09-03"), recurrence: RecurrenceRule(frequency: .weekly)))
        let noon = DateMath.date(from: "2026-09-17")
        let evening = noon.addingTimeInterval(4 * 3600)

        store.skipEvent(id: "evt-rec", on: noon)
        store.skipEvent(id: "evt-rec", on: evening)
        // Fixed `today` before the skipped day: a future skip, independent of the real clock.
        let earlierToday = DateMath.date(from: "2026-09-01")
        store.skipReminder(id: "rem-rec", on: noon, today: earlierToday)
        store.skipReminder(id: "rem-rec", on: evening, today: earlierToday)

        #expect(store.events.first { $0.id == "evt-rec" }?.exceptionDates.count == 1)
        #expect(store.reminders.first { $0.id == "rem-rec" }?.exceptionDates.count == 1)
    }

    // MARK: - Resolving an overdue recurring reminder clears the earlier misses

    private let cal = Calendar(identifier: .gregorian)

    /// Fixed "now": Sunday 2026-09-20, 10:00 local. Never `Date()`.
    private var fixedToday: Date { dt("2026-09-20", hour: 10, minute: 0) }

    private func dt(_ iso: String, hour: Int, minute: Int) -> Date {
        let c = DateMath.components(iso)
        return cal.date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: hour, minute: minute))!
    }

    @MainActor
    private func agenda(_ store: PlannerStore) -> [AgendaItem] {
        buildAgendaItems(events: [], reminders: store.reminders, in: AgendaWindow.range(around: fixedToday), today: fixedToday)
    }

    @MainActor
    private func overdueItem(_ store: PlannerStore) -> AgendaItem? {
        agenda(store).first { $0.isOverdue }
    }

    @MainActor
    private func overdueDays(_ store: PlannerStore) -> [String] {
        agenda(store).filter(\.isOverdue).map { isoDays([$0.occurrence])[0] }
    }

    @MainActor
    private func upcomingDays(_ store: PlannerStore) -> [String] {
        agenda(store).filter { !$0.isOverdue && !$0.isCompleted }.map { isoDays([$0.occurrence])[0] }
    }

    /// A store holding a weekly (Sundays, 09:30) reminder: Aug 30, Sep 6 and Sep 13 are missed,
    /// Sep 20 is today, Sep 27 onward is upcoming.
    @MainActor
    private func makeWeeklyStore() -> (PlannerStore, PlannerFile) {
        let (store, file, _) = makeStore()
        start(store, around: fixedToday)
        store.addReminder(Reminder(id: "rem-w", title: "Weekly review", dueDate: dt("2026-08-30", hour: 9, minute: 30), recurrence: RecurrenceRule(frequency: .weekly)))
        return (store, file)
    }

    @Test("completing the latest missed weekly occurrence clears the earlier misses and makes exactly one completed copy")
    @MainActor
    func completeLatestMissedClearsEarlierMisses() throws {
        let (store, _) = makeWeeklyStore()
        #expect(overdueDays(store) == ["2026-09-13"])
        let overdue = try #require(overdueItem(store))

        store.completeReminder(id: "rem-w", on: overdue.occurrence, today: fixedToday)

        #expect(overdueDays(store).isEmpty)
        // Only today's occurrence and later remain.
        #expect(upcomingDays(store).prefix(3) == ["2026-09-20", "2026-09-27", "2026-10-04"])
        let completed = store.reminders.filter(\.isCompleted)
        #expect(completed.count == 1)
        #expect(completed.first?.dueDate == overdue.occurrence)
        // Aug 30, Sep 6 (cleared) and Sep 13 (completed) are all exdated on the master.
        let master = try #require(store.reminders.first { $0.id == "rem-w" })
        #expect(isoDays(master.exceptionDates).sorted() == ["2026-08-30", "2026-09-06", "2026-09-13"])
        #expect(store.error == nil)
    }

    @Test("skipping the latest missed weekly occurrence clears the earlier misses and makes no completed copy")
    @MainActor
    func skipLatestMissedClearsEarlierMisses() throws {
        let (store, _) = makeWeeklyStore()
        let overdue = try #require(overdueItem(store))

        store.skipReminder(id: "rem-w", on: overdue.occurrence, today: fixedToday)

        #expect(overdueDays(store).isEmpty)
        #expect(upcomingDays(store).prefix(2) == ["2026-09-20", "2026-09-27"])
        #expect(store.reminders.filter(\.isCompleted).isEmpty)
        #expect(store.reminders.count == 1)
        let master = try #require(store.reminders.first { $0.id == "rem-w" })
        #expect(isoDays(master.exceptionDates).sorted() == ["2026-08-30", "2026-09-06", "2026-09-13"])
    }

    @Test("completing or skipping TODAY's occurrence leaves the overdue row alone")
    @MainActor
    func resolvingTodayDoesNotClearOverdue() throws {
        let (completeStore, _) = makeWeeklyStore()
        completeStore.completeReminder(id: "rem-w", on: dt("2026-09-20", hour: 9, minute: 30), today: fixedToday)
        #expect(overdueDays(completeStore) == ["2026-09-13"])
        let completeMaster = try #require(completeStore.reminders.first { $0.id == "rem-w" })
        #expect(completeMaster.exceptionDates.count == 1)
        #expect(completeStore.reminders.filter(\.isCompleted).count == 1)

        let (skipStore, _) = makeWeeklyStore()
        skipStore.skipReminder(id: "rem-w", on: dt("2026-09-20", hour: 9, minute: 30), today: fixedToday)
        #expect(overdueDays(skipStore) == ["2026-09-13"])
        let skipMaster = try #require(skipStore.reminders.first { $0.id == "rem-w" })
        #expect(skipMaster.exceptionDates.count == 1)
    }

    @Test("resolving a future occurrence does not clear anything either")
    @MainActor
    func resolvingFutureDoesNotClearOverdue() throws {
        let (store, _) = makeWeeklyStore()
        store.skipReminder(id: "rem-w", on: dt("2026-09-27", hour: 9, minute: 30), today: fixedToday)
        #expect(overdueDays(store) == ["2026-09-13"])
        let master = try #require(store.reminders.first { $0.id == "rem-w" })
        #expect(master.exceptionDates.count == 1)
    }

    @Test("a daily recurring reminder gets no extra exceptions")
    @MainActor
    func dailyReminderIsUnaffected() throws {
        let (store, _, _) = makeStore()
        start(store, around: fixedToday)
        store.addReminder(Reminder(id: "rem-d", title: "Vitamins", dueDate: dt("2026-09-10", hour: 9, minute: 30), recurrence: RecurrenceRule(frequency: .daily)))

        store.completeReminder(id: "rem-d", on: dt("2026-09-15", hour: 9, minute: 30), today: fixedToday)
        let afterComplete = try #require(store.reminders.first { $0.id == "rem-d" })
        #expect(afterComplete.exceptionDates.count == 1)

        store.skipReminder(id: "rem-d", on: dt("2026-09-16", hour: 9, minute: 30), today: fixedToday)
        let afterSkip = try #require(store.reminders.first { $0.id == "rem-d" })
        #expect(afterSkip.exceptionDates.count == 2)
    }

    @Test("a monthly reminder behaves like the weekly one")
    @MainActor
    func monthlyClearsEarlierMisses() throws {
        let (store, _, _) = makeStore()
        start(store, around: fixedToday)
        // Jun 25, Jul 25 and Aug 25 are missed; Sep 25 and Oct 25 are upcoming.
        store.addReminder(Reminder(id: "rem-m", title: "Pay card", dueDate: dt("2026-06-25", hour: 9, minute: 30), recurrence: RecurrenceRule(frequency: .monthly)))
        #expect(overdueDays(store) == ["2026-08-25"])
        let overdue = try #require(overdueItem(store))

        store.completeReminder(id: "rem-m", on: overdue.occurrence, today: fixedToday)

        #expect(overdueDays(store).isEmpty)
        #expect(upcomingDays(store) == ["2026-09-25", "2026-10-25"])
        #expect(store.reminders.filter(\.isCompleted).count == 1)
        let master = try #require(store.reminders.first { $0.id == "rem-m" })
        #expect(isoDays(master.exceptionDates).sorted() == ["2026-06-25", "2026-07-25", "2026-08-25"])
    }

    @Test("only misses inside the overdue lookback are cleared")
    @MainActor
    func clearingIsBoundedByLookback() throws {
        let (store, _, _) = makeStore()
        start(store, around: fixedToday)
        // Sundays since January. The lookback starts 90 days before Sep 20 = Jun 22, so the
        // cleared misses are Jun 28 ... Sep 6 (11 Sundays) plus the resolved Sep 13.
        store.addReminder(Reminder(id: "rem-w", title: "Weekly review", dueDate: dt("2026-01-04", hour: 9, minute: 30), recurrence: RecurrenceRule(frequency: .weekly)))

        store.skipReminder(id: "rem-w", on: dt("2026-09-13", hour: 9, minute: 30), today: fixedToday)

        let master = try #require(store.reminders.first { $0.id == "rem-w" })
        let days = isoDays(master.exceptionDates).sorted()
        #expect(days.count == 12)
        #expect(days.first == "2026-06-28")
        #expect(days.last == "2026-09-13")
    }

    @Test("clearing earlier misses persists across a fresh store over the same directory")
    @MainActor
    func clearingPersists() throws {
        let (store, file) = makeWeeklyStore()
        let overdue = try #require(overdueItem(store))
        store.completeReminder(id: "rem-w", on: overdue.occurrence, today: fixedToday)

        let reloaded = PlannerStore(file: file)
        start(reloaded, around: fixedToday)

        #expect(overdueDays(reloaded).isEmpty)
        #expect(upcomingDays(reloaded).prefix(2) == ["2026-09-20", "2026-09-27"])
        let master = try #require(reloaded.reminders.first { $0.id == "rem-w" })
        #expect(isoDays(master.exceptionDates).sorted() == ["2026-08-30", "2026-09-06", "2026-09-13"])
        #expect(reloaded.reminders.filter(\.isCompleted).count == 1)
    }

    @Test("skip on a non-recurring or unknown item is a no-op and writes nothing")
    @MainActor
    func skipOnNonRecurringOrUnknownIsNoOp() throws {
        let (store, _, root) = makeStore()
        start(store, around: Self.anchor)
        store.addEvent(Event(id: "evt-1", title: "Standup", start: DateMath.date(from: "2026-09-17")))
        store.addReminder(Reminder(id: "rem-1", title: "Buy milk", dueDate: DateMath.date(from: "2026-09-17")))
        let events = store.events
        let reminders = store.reminders
        // Delete the files so any rewrite by a no-op call would show up as a reappearance.
        try FileManager.default.removeItem(at: docsURL(root, sept.fileName))

        store.skipEvent(id: "evt-1", on: DateMath.date(from: "2026-09-17"))
        store.skipReminder(id: "rem-1", on: DateMath.date(from: "2026-09-17"))
        store.skipEvent(id: "nope", on: DateMath.date(from: "2026-09-17"))
        store.skipReminder(id: "nope", on: DateMath.date(from: "2026-09-17"))

        #expect(store.events == events)
        #expect(store.reminders == reminders)
        #expect(store.error == nil)
        #expect(!FileManager.default.fileExists(atPath: docsURL(root, sept.fileName).path))
        #expect(!FileManager.default.fileExists(atPath: docsURL(root, "recurring.ics").path))
    }

    // MARK: - loadMonths(covering:)

    /// Writes a one-event month file straight to the store's docs directory.
    private func seedMonth(_ root: URL, _ month: YearMonth, title: String, day: String) throws {
        let docs = root.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let content = ICSSerializer.serialize(events: [Event(title: title, start: DateMath.date(from: day))], reminders: [])
        try content.write(to: docs.appendingPathComponent(month.fileName), atomically: true, encoding: .utf8)
    }

    @Test("loadMonths loads months outside the initial window, and their items appear")
    @MainActor
    func loadMonthsLoadsMonthsOutsideInitialWindow() throws {
        let (store, _, root) = makeStore()
        try seedMonth(root, YearMonth(year: 2026, month0: 8), title: "Sept item", day: "2026-09-02")
        try seedMonth(root, YearMonth(year: 2027, month0: 0), title: "Jan item", day: "2027-01-15")
        start(store, around: Self.anchor)
        #expect(store.events.map(\.title) == ["Sept item"])

        store.loadMonths(covering: AgendaWindow.range(around: DateMath.date(from: "2027-01-15")))

        #expect(Set(store.events.map(\.title)) == ["Sept item", "Jan item"])
        #expect(store.error == nil)
    }

    @Test("loadMonths loads every month from the start month through the end month inclusive")
    @MainActor
    func loadMonthsCoversEveryMonthInclusive() throws {
        let (store, _, root) = makeStore()
        try seedMonth(root, YearMonth(year: 2026, month0: 11), title: "Dec", day: "2026-12-10")
        try seedMonth(root, YearMonth(year: 2027, month0: 0), title: "Jan", day: "2027-01-10")
        try seedMonth(root, YearMonth(year: 2027, month0: 1), title: "Feb", day: "2027-02-10")
        try seedMonth(root, YearMonth(year: 2027, month0: 2), title: "Mar", day: "2027-03-10")
        start(store, around: Self.anchor)

        // 2026-12-20 ... 2027-02-14: touches Dec, Jan, Feb (a year boundary), not Mar.
        store.loadMonths(covering: DateMath.date(from: "2026-12-20")...DateMath.date(from: "2027-02-14"))

        #expect(Set(store.events.map(\.title)) == ["Dec", "Jan", "Feb"])
    }

    @Test("loadMonths does not re-read a month that is already loaded")
    @MainActor
    func loadMonthsDoesNotRereadLoadedMonths() throws {
        let (store, _, root) = makeStore()
        try seedMonth(root, sept, title: "Original", day: "2026-09-02")
        start(store, around: Self.anchor)
        #expect(store.events.map(\.title) == ["Original"])

        // Change the file behind the store's back: a re-read would pick this up.
        try seedMonth(root, sept, title: "Changed on disk", day: "2026-09-02")
        store.loadMonths(covering: AgendaWindow.range(around: Self.anchor))

        #expect(store.events.map(\.title) == ["Original"])
    }

    @Test("a failing month read sets error, loads nothing for it, and stays retryable")
    @MainActor
    func loadMonthsFailureIsRetryable() throws {
        let (store, _, root) = makeStore()
        start(store, around: Self.anchor)
        let jan = YearMonth(year: 2027, month0: 0)
        let docs = root.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try Data([0xFF, 0xFE, 0x00]).write(to: docs.appendingPathComponent(jan.fileName))
        let janRange = AgendaWindow.range(around: DateMath.date(from: "2027-01-15"))

        store.loadMonths(covering: janRange)

        #expect(store.error?.contains(jan.fileName) == true)
        #expect(store.events.isEmpty)

        // The file is repaired; a second call must read it rather than treat Jan as loaded/empty.
        store.error = nil
        try seedMonth(root, jan, title: "Jan item", day: "2027-01-15")
        store.loadMonths(covering: janRange)

        #expect(store.error == nil)
        #expect(store.events.map(\.title) == ["Jan item"])
    }
}
