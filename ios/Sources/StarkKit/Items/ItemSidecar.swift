// ios/Sources/StarkKit/Items/ItemSidecar.swift
import Foundation

/// One outcome mark for an Apple item. The day it belongs to is derived from `record.date`
/// at read time (see `ItemSidecar`), never stored.
public struct OutcomeEntry: Codable, Equatable, Sendable {
    public var identifier: String
    public var externalID: String?
    public var record: EventOutcomeRecord

    public init(identifier: String, externalID: String?, record: EventOutcomeRecord) {
        self.identifier = identifier
        self.externalID = externalID
        self.record = record
    }
}

/// Everything Stark keeps locally about Apple-owned items: plan blocks, event outcomes and the
/// import ledger. Plain data; never holds absolute file paths.
///
/// Files written before 2026-11-17 may also hold a `bridgeLedger` key (the removed Claude Code
/// bridge). It is ignored on decode and dropped on the next save; no version change.
public struct SidecarData: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    /// A block's `reminderID` holds the Apple identifier of the reminder it plans.
    public var plans: [PlanBlock]
    /// Written sorted by (identifier, externalID, date) so identical data gives identical bytes.
    public var outcomes: [OutcomeEntry]
    /// Apple identifier -> external identifier, for re-matching plans and ledger entries.
    public var externalIDs: [String: String]
    /// Phase 2 import: local item id -> Apple identifier of the copy created in Apple.
    public var importLedger: [String: String]
    /// When the import last finished (nil = never).
    public var importedAt: Date?

    public init(
        version: Int = SidecarData.currentVersion,
        plans: [PlanBlock] = [],
        outcomes: [OutcomeEntry] = [],
        externalIDs: [String: String] = [:],
        importLedger: [String: String] = [:],
        importedAt: Date? = nil
    ) {
        self.version = version
        self.plans = plans
        self.outcomes = outcomes
        self.externalIDs = externalIDs
        self.importLedger = importLedger
        self.importedAt = importedAt
    }

    private enum CodingKeys: String, CodingKey {
        case version, plans, outcomes, externalIDs, importLedger, importedAt
    }

    /// Missing keys (a version 1 file) decode to empty defaults; the version stays as written
    /// until the next save.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        plans = try c.decodeIfPresent([PlanBlock].self, forKey: .plans) ?? []
        outcomes = try c.decodeIfPresent([OutcomeEntry].self, forKey: .outcomes) ?? []
        externalIDs = try c.decodeIfPresent([String: String].self, forKey: .externalIDs) ?? [:]
        importLedger = try c.decodeIfPresent([String: String].self, forKey: .importLedger) ?? [:]
        importedAt = try c.decodeIfPresent(Date.self, forKey: .importedAt)
    }
}

/// Everything the import writes for one local item, saved together in one sidecar write.
public struct ImportRecord: Equatable, Sendable {
    public var localID: String
    public var identifier: String
    public var externalID: String?
    public var plans: [PlanBlock]
    public var outcomes: [EventOutcomeRecord]

    public init(localID: String, identifier: String, externalID: String?, plans: [PlanBlock] = [], outcomes: [EventOutcomeRecord] = []) {
        self.localID = localID
        self.identifier = identifier
        self.externalID = externalID
        self.plans = plans
        self.outcomes = outcomes
    }
}

public enum ItemSidecarError: Error, Equatable, Sendable {
    /// The file was written by a newer app; refusing to read or overwrite it.
    case unsupportedVersion(Int)
    /// The file exists but could not be read or decoded. Never treated as empty.
    case unreadable(String)
}

public typealias SidecarWriter = @Sendable (Data, URL) throws -> Void

/// The local sidecar file. Missing file = empty data; any other failure throws.
/// A missing Apple item never deletes records: orphans stay until the user acts.
///
/// Day rule: an outcome belongs to the calendar day of its `record.date` in the injected calendar
/// at READ time (`calendar.isDate(_:inSameDayAs:)`); a plan block belongs to the day of its `start`
/// the same way. Nothing day-shaped is stored, so a time-zone change re-buckets by the new zone.
public actor ItemSidecar {
    private let fileURL: URL
    private let calendar: Calendar
    private let writer: SidecarWriter

    /// Atomic write: temp file in the same directory, then replace.
    public static let atomicWriter: SidecarWriter = { data, url in
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// `calendar` decides which local day a plan block or outcome belongs to.
    public init(fileURL: URL, calendar: Calendar = .current, writer: @escaping SidecarWriter = ItemSidecar.atomicWriter) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.writer = writer
    }

    public func load() throws -> SidecarData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return SidecarData() }
        let data: SidecarData
        do {
            let raw = try Data(contentsOf: fileURL)
            data = try Self.decoder.decode(SidecarData.self, from: raw)
        } catch {
            throw ItemSidecarError.unreadable(error.localizedDescription)
        }
        guard data.version <= SidecarData.currentVersion else {
            throw ItemSidecarError.unsupportedVersion(data.version)
        }
        return data
    }

    /// Loads, applies `change`, writes. If the load or write fails nothing on disk changes.
    public func update(_ change: (inout SidecarData) -> Void) throws {
        var data = try load()
        data.version = SidecarData.currentVersion
        change(&data)
        data.outcomes.sort(by: Self.outcomeOrder)
        try writer(try Self.encoder.encode(data), fileURL)
    }

    // MARK: Plans

    public func plans(on day: Date) throws -> [PlanBlock] {
        return try load().plans.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    /// Replaces only `day`'s blocks. `externalIDs` maps Apple identifier -> external identifier.
    public func replacePlans(on day: Date, with blocks: [PlanBlock], externalIDs: [String: String] = [:]) throws {
        try update { data in
            data.plans.removeAll { calendar.isDate($0.start, inSameDayAs: day) }
            data.plans.append(contentsOf: blocks)
            data.externalIDs.merge(externalIDs) { _, new in new }
        }
    }

    /// Blocks for an item: by identifier first, then by any stored identifier sharing `externalID`.
    public func planBlocks(for identifier: String, externalID: String?) throws -> [PlanBlock] {
        let data = try load()
        let direct = data.plans.filter { $0.reminderID == identifier }
        if !direct.isEmpty { return direct }
        guard let externalID else { return [] }
        let stored = Set(data.externalIDs.filter { $0.value == externalID }.keys)
        return data.plans.filter { stored.contains($0.reminderID) }
    }

    // MARK: Outcomes

    public func outcome(for identifier: String, externalID: String?, on day: Date) throws -> EventOutcomeRecord? {
        let sameDay = try load().outcomes.filter { calendar.isDate($0.record.date, inSameDayAs: day) }
        let newestFirst = { (list: [OutcomeEntry]) in list.sorted(by: Self.isNewer) }
        if let hit = newestFirst(sameDay.filter { $0.identifier == identifier }).first { return hit.record }
        guard let externalID else { return nil }
        return newestFirst(sameDay.filter { $0.externalID == externalID }).first?.record
    }

    /// Sets the mark for the occurrence on the day of `record.date` (the occurrence start).
    /// Idempotent: replaces any mark for the same identifier or external id on that day. A nil
    /// `externalID` keeps the one already stored.
    public func setOutcome(_ record: EventOutcomeRecord, for identifier: String, externalID: String?) throws {
        try update { data in
            let matches = Self.matcher(calendar, identifier: identifier, externalID: externalID, day: record.date)
            let kept = externalID
                ?? data.outcomes.first { matches($0) && $0.identifier == identifier && $0.externalID != nil }?.externalID
                ?? data.outcomes.first { matches($0) && $0.externalID != nil }?.externalID
            data.outcomes.removeAll(where: matches)
            data.outcomes.append(OutcomeEntry(identifier: identifier, externalID: kept, record: record))
        }
    }

    /// Removes the mark for the identifier (or external id) on the calendar day of `day`.
    public func clearOutcome(for identifier: String, externalID: String?, on day: Date) throws {
        try update { data in
            data.outcomes.removeAll(where: Self.matcher(calendar, identifier: identifier, externalID: externalID, day: day))
        }
    }

    private static func matcher(_ calendar: Calendar, identifier: String, externalID: String?, day: Date) -> (OutcomeEntry) -> Bool {
        { e in
            calendar.isDate(e.record.date, inSameDayAs: day)
                && (e.identifier == identifier || (externalID != nil && e.externalID == externalID))
        }
    }

    // MARK: Import ledger

    public func importedIDs() throws -> Set<String> {
        Set(try load().importLedger.keys)
    }

    /// Writes the ledger entry, external id, re-keyed plan blocks and
    /// outcomes for one imported item in ONE write (all or none).
    public func recordImport(_ item: ImportRecord) throws {
        try update { data in
            data.importLedger[item.localID] = item.identifier
            if let ext = item.externalID { data.externalIDs[item.identifier] = ext }
            for var block in item.plans {
                block.reminderID = item.identifier
                data.plans.removeAll { $0.id == block.id }
                data.plans.append(block)
            }
            for record in item.outcomes {
                data.outcomes.append(OutcomeEntry(identifier: item.identifier, externalID: item.externalID, record: record))
            }
        }
    }

    public func markImportFinished(at date: Date) throws {
        try update { $0.importedAt = date }
    }

    // MARK: Identifier changes

    /// Rewrites every stored reference to `oldID` (plans, outcomes, external-id map).
    /// Collisions with records already under `newID` keep one record deterministically: for outcomes
    /// the newest by `record.date` per day (an existing non-nil external id wins over nil); for the
    /// external-id map the value already stored for `newID`.
    public func remap(oldID: String, newID: String) throws {
        try update { data in
            for i in data.plans.indices where data.plans[i].reminderID == oldID {
                data.plans[i].reminderID = newID
            }
            var merged: [OutcomeEntry] = []
            var moved: [OutcomeEntry] = []
            for var e in data.outcomes {
                if e.identifier == oldID { e.identifier = newID; moved.append(e) } else { merged.append(e) }
            }
            for e in moved {
                if let i = merged.firstIndex(where: {
                    $0.identifier == newID && self.calendar.isDate($0.record.date, inSameDayAs: e.record.date)
                }) {
                    let existing = merged[i]
                    var winner = Self.isNewer(e, existing) ? e : existing
                    winner.externalID = existing.externalID ?? e.externalID
                    merged[i] = winner
                } else {
                    merged.append(e)
                }
            }
            data.outcomes = merged
            if let ext = data.externalIDs.removeValue(forKey: oldID), data.externalIDs[newID] == nil {
                data.externalIDs[newID] = ext
            }
        }
    }

    // MARK: Coding

    /// Recency: `a` is newer than `b` by `record.date` first; ties fall to outcome, identifier,
    /// externalID so the choice is deterministic. Not the storage order.
    private static func isNewer(_ a: OutcomeEntry, _ b: OutcomeEntry) -> Bool {
        if a.record.date != b.record.date { return a.record.date > b.record.date }
        if a.record.outcome != b.record.outcome { return a.record.outcome.rawValue > b.record.outcome.rawValue }
        if a.identifier != b.identifier { return a.identifier > b.identifier }
        return (a.externalID ?? "") > (b.externalID ?? "")
    }

    /// Storage sort only, ascending by (identifier, externalID, date, outcome) so ordering is total and deterministic.
    private static func outcomeOrder(_ a: OutcomeEntry, _ b: OutcomeEntry) -> Bool {
        if a.identifier != b.identifier { return a.identifier < b.identifier }
        let ax = a.externalID ?? "", bx = b.externalID ?? ""
        if ax != bx { return ax < bx }
        if a.record.date != b.record.date { return a.record.date < b.record.date }
        return a.record.outcome.rawValue < b.record.outcome.rawValue
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
