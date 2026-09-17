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
    func missingMonthIsEmpty() {
        let (directory, pending) = makeTempDirs()
        let file = PlannerFile(directory: directory, pendingDirectory: pending)

        let result = file.loadMonth(YearMonth(year: 2026, month0: 8))

        #expect(result.events.isEmpty)
        #expect(result.reminders.isEmpty)
    }

    @Test("saveMonth then loadMonth round-trips items")
    func saveThenLoadRoundTrips() throws {
        let (directory, pending) = makeTempDirs()
        let file = PlannerFile(directory: directory, pendingDirectory: pending)
        let event = Event(title: "Standup", start: DateMath.date(from: "2026-09-17"))

        try file.saveMonth(YearMonth(year: 2026, month0: 8), events: [event], reminders: [])
        let result = file.loadMonth(YearMonth(year: 2026, month0: 8))

        #expect(result.events.map(\.title) == ["Standup"])
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
        #expect(file.loadMonth(YearMonth(year: 2026, month0: 8)).events.map(\.title) == ["Standup"])
    }
}
