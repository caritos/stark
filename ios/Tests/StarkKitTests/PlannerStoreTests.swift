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

    /// Starts the store with the same window `AgendaView` actually displays, so tests can't
    /// drift from the real app's window the way the original ± 1 month bug did.
    @MainActor
    private func start(_ store: PlannerStore, around date: Date) {
        let range = AgendaWindow.range(around: date)
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
}
