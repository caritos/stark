import Testing
import Foundation
@testable import StarkKit

@Suite struct ItemSidecarImportLedgerTests {
    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sidecar-\(UUID().uuidString)")
            .appendingPathComponent("sidecar.json")
    }

    private func copyFixture() throws -> URL {
        let src = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sidecar-v1.json")
        let dst = tempURL()
        try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: src, to: dst)
        return dst
    }

    private func record(_ id: String = "local-1") -> ImportRecord {
        let d = Date(timeIntervalSince1970: 1_800_100_000)
        return ImportRecord(
            localID: id,
            identifier: "apple-new-\(id)",
            externalID: "ext-new-\(id)",
            plans: [PlanBlock(id: "pb-\(id)", reminderID: id, occurrence: d, start: d, minutes: 45)],
            outcomes: [EventOutcomeRecord(date: d, outcome: .skipped, recordedAt: d)])
    }

    final class WriteCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
        func bump() { lock.lock(); n += 1; lock.unlock() }
    }

    @Test func loadsVersion1FileAndUpgrades() async throws {
        let url = try copyFixture()
        let sidecar = ItemSidecar(fileURL: url, calendar: Self.utc)
        let before = try await sidecar.load()
        #expect(before.version == 1)
        #expect(before.importLedger.isEmpty)
        #expect(before.importedAt == nil)

        try await sidecar.recordImport(record())
        let after = try await sidecar.load()
        #expect(after.version == 2)
        #expect(after.plans.filter { $0.id == "blk-1" } == before.plans)
        #expect(after.outcomes.contains(before.outcomes[0]))
        #expect(after.externalIDs["apple-rem-1"] == "ext-rem-1")
        #expect(after.externalIDs["apple-rem-2"] == "ext-rem-2")
        #expect(after.importLedger == ["local-1": "apple-new-local-1"])
        #expect(after.externalIDs["apple-new-local-1"] == "ext-new-local-1")
        let block = try #require(after.plans.first { $0.id == "pb-local-1" })
        #expect(block.reminderID == "apple-new-local-1")
        let outcome = try #require(after.outcomes.first { $0.identifier == "apple-new-local-1" })
        #expect(outcome.externalID == "ext-new-local-1")
        #expect(outcome.record.outcome == .skipped)
        #expect(try await sidecar.importedIDs() == ["local-1"])
    }

    @Test func recordImportWritesAllPartsInOneWrite() async throws {
        let counter = WriteCounter()
        let writer: SidecarWriter = { data, url in
            counter.bump()
            try ItemSidecar.atomicWriter(data, url)
        }
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc, writer: writer)
        try await sidecar.recordImport(record("a"))
        #expect(counter.count == 1)
        try await sidecar.recordImport(record("b"))
        #expect(counter.count == 2)
    }

    @Test func failedWriteChangesNothing() async throws {
        let url = try copyFixture()
        struct Boom: Error {}
        let failing = ItemSidecar(fileURL: url, calendar: Self.utc, writer: { _, _ in throw Boom() })
        let before = try await ItemSidecar(fileURL: url, calendar: Self.utc).load()
        await #expect(throws: Boom.self) { try await failing.recordImport(record()) }
        let after = try await ItemSidecar(fileURL: url, calendar: Self.utc).load()
        #expect(after == before)
    }

    @Test func version3FileIsRefused() async throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":3,"plans":[],"outcomes":[],"externalIDs":{}}"#.utf8).write(to: url)
        let sidecar = ItemSidecar(fileURL: url, calendar: Self.utc)
        await #expect(throws: ItemSidecarError.unsupportedVersion(3)) { _ = try await sidecar.load() }
        await #expect(throws: ItemSidecarError.unsupportedVersion(3)) { try await sidecar.recordImport(record()) }
    }

    @Test func corruptFileThrowsNotEmpty() async throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        let sidecar = ItemSidecar(fileURL: url, calendar: Self.utc)
        await #expect(throws: ItemSidecarError.self) { _ = try await sidecar.importedIDs() }
        await #expect(throws: ItemSidecarError.self) { try await sidecar.markImportFinished(at: Date()) }
    }

    // MARK: Files written while the Claude Code bridge existed (removed 2026-11-17)

    /// The raw top-level keys of the file as written to disk.
    private func rawKeys(_ url: URL) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return Set(try #require(object as? [String: Any]).keys)
    }

    @Test func oldSidecarWithBridgeLedgerKeyStillLoads() async throws {
        let url = try copyFixture()
        #expect(try rawKeys(url).contains("bridgeLedger"))
        let data = try await ItemSidecar(fileURL: url, calendar: Self.utc).load()
        #expect(data.version == 1)
        #expect(data.plans.map(\.id) == ["blk-1"])
        #expect(data.plans.first?.reminderID == "apple-rem-1")
        #expect(data.outcomes.map(\.identifier) == ["apple-evt-1"])
        #expect(data.externalIDs == ["apple-rem-1": "ext-rem-1", "apple-rem-2": "ext-rem-2"])
        #expect(data.importLedger.isEmpty)
    }

    @Test func v2SidecarWithImportLedgerAndBridgeLedgerKeyStillLoads() async throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"""
        {"bridgeLedger":{"bridge-1":"apple-rem-2","local-1":"apple-new-local-1"},\#
        "externalIDs":{"apple-new-local-1":"ext-new-local-1"},\#
        "importLedger":{"local-1":"apple-new-local-1"},"importedAt":"2027-01-16T10:00:00Z",\#
        "outcomes":[],"plans":[],"version":2}
        """#.utf8).write(to: url)
        let sidecar = ItemSidecar(fileURL: url, calendar: Self.utc)
        let data = try await sidecar.load()
        #expect(data.version == 2)
        #expect(data.importLedger == ["local-1": "apple-new-local-1"])
        #expect(data.externalIDs == ["apple-new-local-1": "ext-new-local-1"])
        #expect(data.importedAt == ISO8601DateFormatter().date(from: "2027-01-16T10:00:00Z"))
        #expect(try await sidecar.importedIDs() == ["local-1"])
    }

    @Test func recordImportNoLongerWritesBridgeLedger() async throws {
        let url = try copyFixture()
        let sidecar = ItemSidecar(fileURL: url, calendar: Self.utc)
        try await sidecar.recordImport(record())
        let keys = try rawKeys(url)
        #expect(!keys.contains("bridgeLedger"))
        #expect(keys.contains("importLedger"))
        let after = try await sidecar.load()
        #expect(after.importLedger == ["local-1": "apple-new-local-1"])
        #expect(after.plans.contains { $0.id == "blk-1" })
        #expect(after.externalIDs["apple-rem-2"] == "ext-rem-2")
    }

    @Test func markImportFinishedStoresDate() async throws {
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc)
        let d = Date(timeIntervalSince1970: 1_800_200_000)
        try await sidecar.markImportFinished(at: d)
        let loaded = try await sidecar.load()
        #expect(loaded.importedAt == d)
        #expect(loaded.version == 2)
    }
}
