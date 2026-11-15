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
        let rec17 = EventOutcomeRecord(date: day("2026-11-17"), outcome: .attended)
        try await s.setOutcome(rec17, for: "E1", externalID: "X1", on: day("2026-11-17"))
        #expect(try await s.load().outcomes.count == 2)
        try await s.setOutcome(nil, for: "E1", externalID: nil, on: d)
        #expect(try await s.outcome(for: "E1", externalID: "X1", on: d) == nil)
        #expect(try await s.outcome(for: "E1", externalID: nil, on: day("2026-11-17")) == rec17)
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
        let entries = try await s.load().outcomes
        #expect(entries.map(\.identifier) == ["NEW"])
        #expect(entries.first?.externalID == "X1")
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

    // MARK: fix round 1

    private var ny: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func nyDate(_ d: Int, _ h: Int, _ m: Int) -> Date {
        ny.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    @Test("setOutcome with a nil external id keeps the stored one")
    func setOutcomeKeepsExternalID() async throws {
        let s = sidecar(tempFile())
        let d = day("2026-11-16")
        try await s.setOutcome(EventOutcomeRecord(date: d, outcome: .attended), for: "E1", externalID: "X1", on: d)
        try await s.setOutcome(EventOutcomeRecord(date: d, outcome: .skipped), for: "E1", externalID: nil, on: d)
        let entries = try await s.load().outcomes
        #expect(entries.count == 1)
        #expect(entries.first?.externalID == "X1")
        #expect(entries.first?.record.outcome == .skipped)
    }

    @Test("remap onto an existing outcome keeps one record, the newest, and an existing external id")
    func remapOutcomeCollision() async throws {
        let s = sidecar(tempFile())
        let older = EventOutcomeRecord(date: day("2026-11-16", hour: 8), outcome: .attended)
        let newer = EventOutcomeRecord(date: day("2026-11-16", hour: 18), outcome: .skipped)
        try await s.setOutcome(older, for: "NEW", externalID: nil, on: older.date)
        try await s.setOutcome(newer, for: "OLD", externalID: "X1", on: newer.date)
        try await s.remap(oldID: "OLD", newID: "NEW")
        let entries = try await s.load().outcomes
        #expect(entries.count == 1)
        #expect(entries[0].identifier == "NEW")
        #expect(entries[0].record == newer)
        #expect(entries[0].externalID == "X1")
        // A different day for NEW is untouched.
        try await s.setOutcome(EventOutcomeRecord(date: day("2026-11-20"), outcome: .attended), for: "OLD", externalID: nil, on: day("2026-11-20"))
        try await s.remap(oldID: "OLD", newID: "NEW")
        #expect(try await s.load().outcomes.count == 2)
    }

    @Test("remap keeps an existing external id for the new identifier and moves plans and ledger")
    func remapExternalIDsAndRest() async throws {
        let s = sidecar(tempFile())
        try await s.replacePlans(on: day("2026-11-16"), with: [
            block("p1", ref: "OLD", on: "2026-11-16"), block("p2", ref: "OTHER", on: "2026-11-16", hour: 11),
        ], externalIDs: ["OLD": "EXT-OLD", "NEW": "EXT-NEW", "OTHER": "EXT-O"])
        try await s.recordBridge(itemID: "b1", identifier: "OLD", externalID: nil)
        try await s.remap(oldID: "OLD", newID: "NEW")
        let data = try await s.load()
        #expect(data.externalIDs == ["NEW": "EXT-NEW", "OTHER": "EXT-O"])
        #expect(data.plans.map(\.reminderID) == ["NEW", "OTHER"])
        #expect(data.bridgeLedger == ["b1": "NEW"])
        try await s.replacePlans(on: day("2026-11-18"), with: [], externalIDs: ["Z": "EXT-Z"])
        try await s.remap(oldID: "Z", newID: "Y")
        #expect(try await s.load().externalIDs["Y"] == "EXT-Z")
    }

    @Test("encoding is deterministic and the outcome shape is readable")
    func deterministicBytes() async throws {
        let url = tempFile()
        let s = sidecar(url)
        for (i, id) in ["Z", "A", "M"].enumerated() {
            let d = day("2026-11-1\(i + 1)")
            try await s.setOutcome(EventOutcomeRecord(date: d, outcome: .attended), for: id, externalID: "X\(id)", on: d)
        }
        let first = try Data(contentsOf: url)
        try await s.update { _ in }
        #expect(try Data(contentsOf: url) == first)
        let decoded = try await s.load()
        #expect(decoded.outcomes.map(\.identifier) == ["A", "M", "Z"])
        let other = tempFile()
        try await sidecar(other).update { $0 = decoded }
        #expect(try Data(contentsOf: other) == first)
        let text = String(decoding: first, as: UTF8.self)
        #expect(text.contains("\"identifier\""))
        #expect(text.contains("\"externalID\""))
        #expect(SidecarData.currentVersion == 1)
    }

    @Test("the external id fallback is deterministic, identifier first, then newest")
    func deterministicFallback() async throws {
        let s = sidecar(tempFile())
        let a = EventOutcomeRecord(date: day("2026-11-16", hour: 8), outcome: .attended)
        let b = EventOutcomeRecord(date: day("2026-11-16", hour: 18), outcome: .skipped)
        try await s.update { $0.outcomes = [
            OutcomeEntry(identifier: "A", externalID: "X", record: a),
            OutcomeEntry(identifier: "B", externalID: "X", record: b),
        ] }
        for _ in 0..<10 {
            #expect(try await s.outcome(for: "NEW", externalID: "X", on: day("2026-11-16")) == b)
        }
        #expect(try await s.outcome(for: "A", externalID: "X", on: day("2026-11-16")) == a)
    }

    @Test("outcomes match by calendar day at read time in a non-UTC zone")
    func outcomeNonUTCBoundary() async throws {
        let url = tempFile()
        let s = ItemSidecar(fileURL: url, calendar: ny)
        let late = nyDate(16, 23, 30)
        let rec = EventOutcomeRecord(date: late, outcome: .attended)
        try await s.setOutcome(rec, for: "E1", externalID: nil, on: late)
        #expect(try await s.outcome(for: "E1", externalID: nil, on: nyDate(16, 8, 0)) == rec)
        #expect(try await s.outcome(for: "E1", externalID: nil, on: nyDate(17, 0, 30)) == nil)
    }

    /// Rule: a mark belongs to the calendar day of its stored instant in the calendar in force at read time.
    @Test("changing the calendar's zone between write and read uses the new zone")
    func outcomeZoneChange() async throws {
        let url = tempFile()
        let instant = day("2026-11-17", hour: 3) // 22:00 on Nov 16 in New York, Nov 17 in UTC
        let rec = EventOutcomeRecord(date: instant, outcome: .attended)
        try await ItemSidecar(fileURL: url, calendar: ny).setOutcome(rec, for: "E1", externalID: nil, on: instant)
        let reader = ItemSidecar(fileURL: url, calendar: utc)
        #expect(try await reader.outcome(for: "E1", externalID: nil, on: day("2026-11-17", hour: 12)) == rec)
        #expect(try await reader.outcome(for: "E1", externalID: nil, on: day("2026-11-16", hour: 12)) == nil)
    }

    @Test("plans bucket by local day at read time in a non-UTC zone")
    func plansNonUTCBoundary() async throws {
        let s = ItemSidecar(fileURL: tempFile(), calendar: ny)
        let late = PlanBlock(id: "p1", reminderID: "A", occurrence: nyDate(16, 9, 0), start: nyDate(16, 23, 30), minutes: 30)
        try await s.replacePlans(on: nyDate(16, 12, 0), with: [late])
        #expect(try await s.plans(on: nyDate(16, 8, 0)).map(\.id) == ["p1"])
        #expect(try await s.plans(on: nyDate(17, 0, 30)).isEmpty)
    }
}
