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

    @Test("a non-recurring event is written to its own month's file")
    @MainActor
    func nonRecurringEventGoesToMonthFile() {
        let (store, file, _) = makeStore()
        store.start(around: DateMath.date(from: "2026-09-01"))

        store.addEvent(Event(title: "Standup", start: DateMath.date(from: "2026-09-17")))

        let onDisk = file.loadMonth(YearMonth(year: 2026, month0: 8))
        #expect(onDisk.events.map(\.title) == ["Standup"])
        #expect(store.events.map(\.title) == ["Standup"])
    }

    @Test("a recurring reminder is written to recurring.ics, not a month file")
    @MainActor
    func recurringReminderGoesToRecurringFile() {
        let (store, file, _) = makeStore()
        store.start(around: DateMath.date(from: "2026-09-01"))

        store.addReminder(Reminder(
            title: "Take out trash",
            dueDate: DateMath.date(from: "2026-09-17"),
            recurrence: RecurrenceRule(frequency: .weekly)
        ))

        let recurring = file.loadRecurring()
        #expect(recurring.reminders.map(\.title) == ["Take out trash"])
        let month = file.loadMonth(YearMonth(year: 2026, month0: 8))
        #expect(month.reminders.isEmpty)
    }

    @Test("completing one occurrence of a recurring reminder exdates the master and logs a completion")
    @MainActor
    func completingRecurringReminderExdatesAndLogs() {
        let (store, file, _) = makeStore()
        store.start(around: DateMath.date(from: "2026-09-01"))
        store.addReminder(Reminder(
            id: "rem-1",
            title: "Take out trash",
            dueDate: DateMath.date(from: "2026-09-17"),
            recurrence: RecurrenceRule(frequency: .weekly)
        ))

        store.completeReminder(id: "rem-1", on: DateMath.date(from: "2026-09-17"))

        let recurring = file.loadRecurring()
        #expect(recurring.reminders.first?.exceptionDates.count == 1)
        let month = file.loadMonth(YearMonth(year: 2026, month0: 8))
        #expect(month.reminders.contains { $0.isCompleted && $0.title == "Take out trash" })
    }
}
