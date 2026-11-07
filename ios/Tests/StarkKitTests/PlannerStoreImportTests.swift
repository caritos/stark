// ios/Tests/StarkKitTests/PlannerStoreImportTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("PlannerStore.importItems")
struct PlannerStoreImportTests {
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

    private let today = DateMath.date(from: "2026-09-01")

    @Test("one-offs go to month files, a recurring reminder to recurring.ics, and survive a fresh store")
    @MainActor
    func routesAndPersists() throws {
        let (store, file, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        start(store, around: today)
        let event = Event(id: "e1", title: "Dentist", start: DateMath.date(from: "2026-09-17"))
        let one = Reminder(id: "r1", title: "Call", dueDate: DateMath.date(from: "2026-09-18"))
        let weekly = Reminder(id: "r2", title: "Trash", dueDate: DateMath.date(from: "2026-09-19"), recurrence: RecurrenceRule(frequency: .weekly))

        let outcome = try store.importItems(events: [event], reminders: [one, weekly])

        #expect(outcome == ImportOutcome(added: 3, alreadyPresent: 0))
        let month = try file.loadMonth(YearMonth(year: 2026, month0: 8))
        #expect(month.events.map(\.id) == ["e1"])
        #expect(month.reminders.map(\.id) == ["r1"])
        #expect(try file.loadRecurring().reminders.map(\.id) == ["r2"])

        let fresh = PlannerStore(file: PlannerFile(directory: root.appendingPathComponent("docs"), pendingDirectory: root.appendingPathComponent("pending")))
        start(fresh, around: today)
        #expect(Set(fresh.events.map(\.id)) == ["e1"])
        #expect(Set(fresh.reminders.map(\.id)) == ["r1", "r2"])
    }

    @Test("importing the same items again adds nothing and leaves files unchanged")
    @MainActor
    func idempotent() throws {
        let (store, file, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        start(store, around: today)
        let event = Event(id: "e1", title: "Dentist", start: DateMath.date(from: "2026-09-17"))
        let weekly = Reminder(id: "r2", title: "Trash", dueDate: DateMath.date(from: "2026-09-19"), recurrence: RecurrenceRule(frequency: .weekly))
        _ = try store.importItems(events: [event], reminders: [weekly])
        let monthURL = root.appendingPathComponent("docs/2026-09.ics")
        let recurringURL = root.appendingPathComponent("docs/recurring.ics")
        let before = (try Data(contentsOf: monthURL), try Data(contentsOf: recurringURL))
        _ = file

        let outcome = try store.importItems(events: [event], reminders: [weekly])

        #expect(outcome == ImportOutcome(added: 0, alreadyPresent: 2))
        #expect(try Data(contentsOf: monthURL) == before.0)
        #expect(try Data(contentsOf: recurringURL) == before.1)
        #expect(store.events.count == 1)
        #expect(store.reminders.count == 1)
    }

    @Test("a duplicate id inside one call is counted alreadyPresent")
    @MainActor
    func duplicateWithinCall() throws {
        let (store, _, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        start(store, around: today)
        let a = Reminder(id: "dup", title: "A", dueDate: DateMath.date(from: "2026-09-18"))
        let b = Reminder(id: "dup", title: "B", dueDate: DateMath.date(from: "2026-09-18"))

        let outcome = try store.importItems(events: [], reminders: [a, b])

        #expect(outcome == ImportOutcome(added: 1, alreadyPresent: 1))
        #expect(store.reminders.map(\.title) == ["A"])
    }

    @Test("an id that exists as a completed copy counts as already present")
    @MainActor
    func completedCopyCounts() throws {
        let (store, _, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        start(store, around: today)
        store.addReminder(Reminder(id: "done1", title: "Old", dueDate: DateMath.date(from: "2026-09-02"), isCompleted: true, completedDate: DateMath.date(from: "2026-09-02")))

        let outcome = try store.importItems(events: [], reminders: [Reminder(id: "done1", title: "Old", dueDate: DateMath.date(from: "2026-09-02"))])

        #expect(outcome == ImportOutcome(added: 0, alreadyPresent: 1))
    }

    @Test("a month outside the started window is loaded first and its existing items are kept")
    @MainActor
    func loadsFarMonth() throws {
        let (store, file, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try file.saveMonth(YearMonth(year: 2027, month0: 2), events: [Event(id: "old", title: "Existing", start: DateMath.date(from: "2027-03-05"))], reminders: [])
        start(store, around: today)
        #expect(!store.events.contains { $0.id == "old" })

        let outcome = try store.importItems(events: [], reminders: [Reminder(id: "far", title: "Far", dueDate: DateMath.date(from: "2027-03-10"))])

        #expect(outcome.added == 1)
        let month = try file.loadMonth(YearMonth(year: 2027, month0: 2))
        #expect(month.events.map(\.id) == ["old"])
        #expect(month.reminders.map(\.id) == ["far"])
    }

    @Test("an unreadable destination month throws and adds nothing from the batch")
    @MainActor
    func unreadableMonthIsAllOrNothing() throws {
        let (store, _, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        start(store, around: today)
        let docs = root.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try Data([0xFF, 0xFE, 0xC0, 0x80]).write(to: docs.appendingPathComponent("2028-01.ics"))
        let ok = Reminder(id: "ok", title: "Fine", dueDate: DateMath.date(from: "2026-09-18"))
        let bad = Reminder(id: "bad", title: "Bad", dueDate: DateMath.date(from: "2028-01-10"))
        let weekly = Reminder(id: "wk", title: "Weekly", dueDate: DateMath.date(from: "2026-09-19"), recurrence: RecurrenceRule(frequency: .weekly))

        #expect(throws: ImportFailure.unreadableMonth("2028-01.ics")) {
            try store.importItems(events: [], reminders: [ok, weekly, bad])
        }

        #expect(store.reminders.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: docs.appendingPathComponent("2026-09.ics").path))
        #expect(!FileManager.default.fileExists(atPath: docs.appendingPathComponent("recurring.ics").path))
    }

    @Test("hostile text round-trips without creating extra components")
    @MainActor
    func injectionRoundTrip() throws {
        let (store, file, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        start(store, around: today)
        let nasty = "a\nb, c; d \\ e\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nSUMMARY:forged 🎯"
        let event = Event(id: "e1", title: nasty, notes: nasty, start: DateMath.date(from: "2026-09-17"), location: nasty)
        let reminder = Reminder(id: "r1", title: nasty, notes: nasty, dueDate: DateMath.date(from: "2026-09-18"))

        _ = try store.importItems(events: [event], reminders: [reminder])

        let month = try file.loadMonth(YearMonth(year: 2026, month0: 8))
        #expect(month.events.count == 1)
        #expect(month.reminders.count == 1)
        let normalised = "a\nb, c; d \\ e\nEND:VEVENT\nBEGIN:VEVENT\nSUMMARY:forged 🎯"
        #expect(month.events[0].title == normalised)
        #expect(month.events[0].notes == normalised)
        #expect(month.events[0].location == normalised)
        #expect(month.reminders[0].title == normalised)
        let raw = try String(contentsOf: root.appendingPathComponent("docs/2026-09.ics"), encoding: .utf8)
        #expect(raw.components(separatedBy: .newlines).filter { $0 == "BEGIN:VEVENT" }.count == 1)
        #expect(raw.components(separatedBy: .newlines).filter { $0 == "BEGIN:VTODO" }.count == 1)
        #expect(!raw.contains("\r\\n") && !raw.replacingOccurrences(of: "\r\n", with: "").contains("\r"))
    }
}
