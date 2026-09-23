// ios/Tests/StarkKitTests/PlannerFileTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("PlannerFile")
struct PlannerFileTests {
    private func makeTempDirs() -> (directory: URL, pending: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (root.appendingPathComponent("docs"), root.appendingPathComponent("pending"))
    }

    @Test("loading a missing month returns an empty result, not an error")
    func missingMonthIsEmpty() throws {
        let (directory, pending) = makeTempDirs()
        let file = PlannerFile(directory: directory, pendingDirectory: pending)

        let result = try file.loadMonth(YearMonth(year: 2026, month0: 8))

        #expect(result.events.isEmpty)
        #expect(result.reminders.isEmpty)
    }

    @Test("a file that exists but can't be read throws, distinct from a merely-missing file")
    func genuineReadFailureThrows() throws {
        let (directory, pending) = makeTempDirs()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Put a directory where the month file should be: `fileExists` returns true (so
        // this must NOT take the "missing file" empty-result path), but reading it as a
        // string genuinely fails.
        let monthURL = directory.appendingPathComponent(YearMonth(year: 2026, month0: 8).fileName)
        try FileManager.default.createDirectory(at: monthURL, withIntermediateDirectories: true)
        let file = PlannerFile(directory: directory, pendingDirectory: pending)

        #expect(throws: (any Error).self) {
            try file.loadMonth(YearMonth(year: 2026, month0: 8))
        }
    }

    @Test("saveMonth then loadMonth round-trips items")
    func saveThenLoadRoundTrips() throws {
        let (directory, pending) = makeTempDirs()
        let file = PlannerFile(directory: directory, pendingDirectory: pending)
        let event = Event(title: "Standup", start: DateMath.date(from: "2026-09-17"))

        try file.saveMonth(YearMonth(year: 2026, month0: 8), events: [event], reminders: [])
        let result = try file.loadMonth(YearMonth(year: 2026, month0: 8))

        #expect(result.events.map(\.title) == ["Standup"])
    }

    @Test("deleteMonth removes an existing month file")
    func deleteMonthRemovesFile() throws {
        let (directory, pending) = makeTempDirs()
        let file = PlannerFile(directory: directory, pendingDirectory: pending)
        let month = YearMonth(year: 2026, month0: 8)
        try file.saveMonth(month, events: [Event(title: "Standup", start: DateMath.date(from: "2026-09-17"))], reminders: [])
        let url = directory.appendingPathComponent(month.fileName)
        #expect(FileManager.default.fileExists(atPath: url.path))

        try file.deleteMonth(month)

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("deleteMonth is a no-op when the month file never existed")
    func deleteMonthNoOpWhenMissing() throws {
        let (directory, pending) = makeTempDirs()
        let file = PlannerFile(directory: directory, pendingDirectory: pending)

        try file.deleteMonth(YearMonth(year: 2026, month0: 8))

        let result = try file.loadMonth(YearMonth(year: 2026, month0: 8))
        #expect(result.events.isEmpty)
    }

    @Test("availableMonths lists every YYYY-MM.ics file, ignoring recurring.ics and non-ics files")
    func availableMonthsListsMonthFiles() throws {
        let (directory, pending) = makeTempDirs()
        let file = PlannerFile(directory: directory, pendingDirectory: pending)
        try file.saveMonth(
            YearMonth(year: 2026, month0: 0),
            events: [],
            reminders: [Reminder(title: "January reminder", dueDate: DateMath.date(from: "2026-01-05"))]
        )
        try file.saveMonth(
            YearMonth(year: 2025, month0: 11),
            events: [Event(title: "December event", start: DateMath.date(from: "2025-12-05"))],
            reminders: []
        )
        try file.saveRecurring(events: [], reminders: [])
        try "not an ics file".write(to: directory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let months = Set(file.availableMonths())

        #expect(months == Set([YearMonth(year: 2026, month0: 0), YearMonth(year: 2025, month0: 11)]))
    }

    @Test("availableMonths returns empty when the directory doesn't exist yet")
    func availableMonthsEmptyWhenMissing() {
        let (directory, pending) = makeTempDirs()
        let file = PlannerFile(directory: directory, pendingDirectory: pending)

        #expect(file.availableMonths().isEmpty)
    }

    @Test("a save failure queues a pending write, retried later")
    func saveFailureQueuesPendingWrite() throws {
        let (directory, pending) = makeTempDirs()
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Create a plain FILE where the target directory should be, forcing every save to fail.
        try Data().write(to: directory)
        let file = PlannerFile(directory: directory, pendingDirectory: pending)
        let event = Event(title: "Standup", start: DateMath.date(from: "2026-09-17"))

        #expect(throws: (any Error).self) {
            try file.saveMonth(YearMonth(year: 2026, month0: 8), events: [event], reminders: [])
        }
        #expect(file.pendingWriteCount == 1)

        // Fix the directory, then retry.
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file.retryPendingWrites()

        #expect(file.pendingWriteCount == 0)
        #expect(try file.loadMonth(YearMonth(year: 2026, month0: 8)).events.map(\.title) == ["Standup"])
    }
}
