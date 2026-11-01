// ios/Tests/StarkKitTests/PlannerStorePlansTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("PlannerStore plans")
struct PlannerStorePlansTests {
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

    private func block(_ reminderID: String, day: String, hour: Int = 9, minutes: Int = 30) -> PlanBlock {
        let start = DateMath.date(from: day).addingTimeInterval(TimeInterval((hour - 12) * 3600))
        return PlanBlock(reminderID: reminderID, occurrence: DateMath.date(from: day), start: start, minutes: minutes)
    }

    @Test("plans survive a reload from disk")
    @MainActor
    func replaceThenReload() {
        let (store, file, _) = makeStore()
        let day = DateMath.date(from: "2026-11-02")
        start(store, around: day)
        let blocks = [block("r1", day: "2026-11-02"), block("r2", day: "2026-11-02", hour: 11)]
        store.replacePlans(on: day, with: blocks)

        let second = PlannerStore(file: file)
        start(second, around: day)
        #expect(second.plans == blocks)
        #expect(second.plans(on: day) == blocks)
    }

    @Test("replacing a day leaves other days alone")
    @MainActor
    func replaceOnlyAffectsThatDay() {
        let (store, _, _) = makeStore()
        let d1 = DateMath.date(from: "2026-11-02"), d2 = DateMath.date(from: "2026-11-03")
        start(store, around: d1)
        let other = block("r1", day: "2026-11-03")
        store.replacePlans(on: d2, with: [other])
        store.replacePlans(on: d1, with: [block("r2", day: "2026-11-02")])
        store.replacePlans(on: d1, with: [block("r3", day: "2026-11-02")])
        #expect(store.plans(on: d2) == [other])
        #expect(store.plans(on: d1).map(\.reminderID) == ["r3"])
        #expect(store.plans.count == 2)
    }

    @Test("deleting a reminder drops its plan blocks")
    @MainActor
    func deleteReminderDropsItsPlans() {
        let (store, file, _) = makeStore()
        let day = DateMath.date(from: "2026-11-02")
        start(store, around: day)
        let reminder = Reminder(title: "Write", dueDate: day)
        store.addReminder(reminder)
        store.replacePlans(on: day, with: [block(reminder.id, day: "2026-11-02"), block("keep", day: "2026-11-02", hour: 11)])
        store.deleteReminder(id: reminder.id)
        #expect(store.plans.map(\.reminderID) == ["keep"])
        let onDisk = try? file.loadMonth(YearMonth(date: day))
        #expect(onDisk?.plans.map(\.reminderID) == ["keep"])
    }

    @Test("a month with only plans keeps its file")
    @MainActor
    func monthWithOnlyPlansKeepsFile() throws {
        let (store, file, root) = makeStore()
        let day = DateMath.date(from: "2026-11-02")
        start(store, around: day)
        let blocks = [block("r1", day: "2026-11-02")]
        store.replacePlans(on: day, with: blocks)
        let path = root.appendingPathComponent("docs/2026-11.ics").path
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try file.loadMonth(YearMonth(date: day)).plans == blocks)
        // Persisting that month again via an unrelated change keeps it too.
        let event = Event(title: "E", start: day)
        store.addEvent(event)
        store.deleteEvent(id: event.id)
        #expect(FileManager.default.fileExists(atPath: path))
        // Clearing the plans empties the month and removes the file.
        store.replacePlans(on: day, with: [])
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("an unreadable month is never deleted or overwritten by replacePlans")
    @MainActor
    func unreadableMonthIsLeftAlone() throws {
        let (store, _, root) = makeStore()
        let day = DateMath.date(from: "2026-11-02")
        // A directory where the month file should be: exists, but cannot be read as text.
        let path = root.appendingPathComponent("docs/2026-11.ics")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        start(store, around: day)
        store.error = nil
        store.replacePlans(on: day, with: [])
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir) && isDir.boolValue)
        #expect(store.error != nil)
        store.error = nil
        store.replacePlans(on: day, with: [block("r1", day: "2026-11-02")])
        #expect(FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir) && isDir.boolValue)
        #expect(store.error != nil)
        #expect(store.plans.isEmpty)
    }

    @Test("blocks starting on another day are ignored")
    @MainActor
    func foreignDayBlocksIgnored() {
        let (store, _, _) = makeStore()
        let d1 = DateMath.date(from: "2026-11-02")
        start(store, around: d1)
        let mine = block("r1", day: "2026-11-02")
        store.replacePlans(on: d1, with: [mine, block("r2", day: "2026-11-05")])
        #expect(store.plans == [mine])
    }

    @Test("a month without plans is byte-identical to the plan-free serializer")
    @MainActor
    func emptyPlansLeavesFileUntouched() throws {
        let (store, _, root) = makeStore()
        let day = DateMath.date(from: "2026-11-02")
        start(store, around: day)
        let event = Event(title: "Standup", start: day)
        store.addEvent(event)
        let data = try Data(contentsOf: root.appendingPathComponent("docs/2026-11.ics"))
        let expected = ICSSerializer.serialize(events: [event], reminders: [])
        #expect(String(decoding: data, as: UTF8.self) == expected)
    }
}
