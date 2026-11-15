// ios/Tests/StarkKitTests/ItemSidecarTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("ItemSidecar")
struct ItemSidecarTests {
    private struct WriteFailed: Error {}

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("sidecar.json")
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ s: String, hour: Int = 9) -> Date {
        utc.date(from: DateComponents(year: Int(s.prefix(4)), month: Int(s.dropFirst(5).prefix(2)),
                                      day: Int(s.suffix(2)), hour: hour))!
    }

    private func sidecar(_ url: URL) -> ItemSidecar { ItemSidecar(fileURL: url, calendar: utc) }

    private func block(_ id: String, ref: String, on d: String, hour: Int = 9) -> PlanBlock {
        PlanBlock(id: id, reminderID: ref, occurrence: day(d), start: day(d, hour: hour), minutes: 30)
    }

    @Test("a missing file loads as empty data with the version set")
    func missingFileIsEmpty() async throws {
        let data = try await sidecar(tempFile()).load()
        #expect(data == SidecarData())
        #expect(data.version == SidecarData.currentVersion)
        #expect(data.plans.isEmpty && data.outcomes.isEmpty && data.bridgeLedger.isEmpty)
    }

    @Test("update then load round-trips through a fresh instance")
    func roundTrip() async throws {
        let url = tempFile()
        try await sidecar(url).update { $0.bridgeLedger["b1"] = "ID-1" }
        let data = try await sidecar(url).load()
        #expect(data.bridgeLedger == ["b1": "ID-1"])
    }

    @Test("a failing write throws and leaves the old file intact")
    func failedWriteKeepsOldFile() async throws {
        let url = tempFile()
        try await sidecar(url).update { $0.bridgeLedger["b1"] = "ID-1" }
        let before = try Data(contentsOf: url)

        let failing = ItemSidecar(fileURL: url, calendar: utc, writer: { _, _ in throw WriteFailed() })
        await #expect(throws: WriteFailed.self) {
            try await failing.update { $0.bridgeLedger["b2"] = "ID-2" }
        }
        #expect(try Data(contentsOf: url) == before)
        #expect(try await sidecar(url).load().bridgeLedger == ["b1": "ID-1"])
    }

    @Test("corrupt JSON throws and the file is left untouched")
    func corruptThrows() async throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        let s = sidecar(url)
        await #expect(throws: (any Error).self) { try await s.load() }
        await #expect(throws: (any Error).self) { try await s.update { $0.bridgeLedger["x"] = "y" } }
        #expect(try Data(contentsOf: url) == Data("{not json".utf8))
    }

    @Test("an unreadable file (a directory in its place) throws, never empty")
    func unreadableThrows() async throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        await #expect(throws: (any Error).self) { try await sidecar(url).load() }
    }

    @Test("an unknown future version throws")
    func futureVersionThrows() async throws {
        let url = tempFile()
        let s = sidecar(url)
        try await s.update { $0.version = SidecarData.currentVersion + 1 }
        await #expect(throws: ItemSidecarError.self) { try await s.load() }
    }

    @Test("plans for a day replace only that day")
    func plansReplaceOnlyThatDay() async throws {
        let s = sidecar(tempFile())
        try await s.replacePlans(on: day("2026-11-16"), with: [block("p1", ref: "A", on: "2026-11-16")])
        try await s.replacePlans(on: day("2026-11-17"), with: [block("p2", ref: "B", on: "2026-11-17")])
        try await s.replacePlans(on: day("2026-11-16"), with: [
            block("p3", ref: "A", on: "2026-11-16", hour: 10),
            block("p4", ref: "C", on: "2026-11-16", hour: 11),
        ])
        #expect(try await s.plans(on: day("2026-11-16", hour: 22)).map(\.id) == ["p3", "p4"])
        #expect(try await s.plans(on: day("2026-11-17")).map(\.id) == ["p2"])
        try await s.replacePlans(on: day("2026-11-16"), with: [])
        #expect(try await s.plans(on: day("2026-11-16")).isEmpty)
        #expect(try await s.plans(on: day("2026-11-17")).count == 1)
    }

    @Test("plan blocks re-match on the external id after the identifier changed")
    func planRematch() async throws {
        let s = sidecar(tempFile())
        try await s.replacePlans(on: day("2026-11-16"), with: [block("p1", ref: "OLD", on: "2026-11-16")],
                                 externalIDs: ["OLD": "EXT-1"])
        #expect(try await s.planBlocks(for: "NEW", externalID: "EXT-1").map(\.id) == ["p1"])
        #expect(try await s.planBlocks(for: "OLD", externalID: nil).map(\.id) == ["p1"])
        #expect(try await s.planBlocks(for: "NEW", externalID: "OTHER").isEmpty)
        try await s.remap(oldID: "OLD", newID: "NEW")
        #expect(try await s.plans(on: day("2026-11-16")).first?.reminderID == "NEW")
        #expect(try await s.planBlocks(for: "NEW", externalID: nil).count == 1)
    }

    @Test("outcomes are idempotent by identifier and day, and nil clears")
    func outcomeSetClear() async throws {
        let s = sidecar(tempFile())
        let d = day("2026-11-16")
        let rec = EventOutcomeRecord(date: d, outcome: .attended)
        try await s.setOutcome(rec, for: "E1", externalID: "X1", on: d)
        try await s.setOutcome(rec, for: "E1", externalID: "X1", on: d)
        #expect(try await s.load().outcomes.count == 1)
        let skipped = EventOutcomeRecord(date: d, outcome: .skipped)
        try await s.setOutcome(skipped, for: "E1", externalID: "X1", on: d)
        #expect(try await s.load().outcomes.count == 1)
        #expect(try await s.outcome(for: "E1", externalID: nil, on: d) == skipped)
        try await s.setOutcome(rec, for: "E1", externalID: "X1", on: day("2026-11-17"))
        #expect(try await s.load().outcomes.count == 2)
        try await s.setOutcome(nil, for: "E1", externalID: nil, on: d)
        #expect(try await s.outcome(for: "E1", externalID: "X1", on: d) == nil)
        #expect(try await s.outcome(for: "E1", externalID: nil, on: day("2026-11-17")) == rec)
        // Clearing again is a no-op.
        try await s.setOutcome(nil, for: "E1", externalID: nil, on: d)
        #expect(try await s.load().outcomes.count == 1)
    }

    @Test("an outcome re-matches on the external id; a missing item keeps its record")
    func outcomeRematchAndOrphan() async throws {
        let s = sidecar(tempFile())
        let d = day("2026-11-16")
        let rec = EventOutcomeRecord(date: d, outcome: .attended)
        try await s.setOutcome(rec, for: "OLD", externalID: "X1", on: d)
        #expect(try await s.outcome(for: "NEW", externalID: "X1", on: d) == rec)
        // Looking up something that exists nowhere deletes nothing.
        #expect(try await s.outcome(for: "GONE", externalID: "Y", on: d) == nil)
        #expect(try await s.load().outcomes.count == 1)
        try await s.remap(oldID: "OLD", newID: "NEW")
        let keys = try await s.load().outcomes.keys
        #expect(keys.map(\.identifier) == ["NEW"])
        #expect(keys.first?.externalID == "X1")
    }

    @Test("bridge ledger records and looks up, re-recording replaces, remap follows")
    func ledger() async throws {
        let s = sidecar(tempFile())
        #expect(try await s.bridgedIdentifier(for: "b1") == nil)
        try await s.recordBridge(itemID: "b1", identifier: "ID-1", externalID: "EXT-1")
        try await s.recordBridge(itemID: "b1", identifier: "ID-1", externalID: "EXT-1")
        #expect(try await s.bridgedIdentifier(for: "b1") == "ID-1")
        #expect(try await s.load().bridgeLedger.count == 1)
        try await s.recordBridge(itemID: "b1", identifier: "ID-2", externalID: nil)
        #expect(try await s.bridgedIdentifier(for: "b1") == "ID-2")
        try await s.remap(oldID: "ID-2", newID: "ID-3")
        #expect(try await s.bridgedIdentifier(for: "b1") == "ID-3")
        #expect(try await s.bridgedIdentifier(for: "nope") == nil)
    }

    @Test("the stored data holds no absolute file paths")
    func noAbsolutePaths() async throws {
        let url = tempFile()
        let s = sidecar(url)
        try await s.recordBridge(itemID: "b1", identifier: "ID-1", externalID: "EXT")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains(NSTemporaryDirectory()))
    }
}
