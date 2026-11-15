// ios/Sources/StarkKit/Items/ItemSidecar.swift
import Foundation

/// Identifies one outcome mark: an Apple item identifier plus its external identifier (used to
/// re-match when the identifier changes) and the local calendar day, `yyyy-MM-dd`.
public struct OutcomeKey: Codable, Hashable, Sendable {
    public var identifier: String
    public var externalID: String?
    public var day: String

    public init(identifier: String, externalID: String?, day: String) {
        self.identifier = identifier
        self.externalID = externalID
        self.day = day
    }
}

/// Everything Stark keeps locally about Apple-owned items: plan blocks, event outcomes and the
/// bridge idempotency ledger. Plain data; never holds absolute file paths.
public struct SidecarData: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// A block's `reminderID` holds the Apple identifier of the reminder it plans.
    public var plans: [PlanBlock]
    public var outcomes: [OutcomeKey: EventOutcomeRecord]
    /// Bridge item id -> Apple identifier.
    public var bridgeLedger: [String: String]
    /// Apple identifier -> external identifier, for re-matching plans and ledger entries.
    public var externalIDs: [String: String]

    public init(
        version: Int = SidecarData.currentVersion,
        plans: [PlanBlock] = [],
        outcomes: [OutcomeKey: EventOutcomeRecord] = [:],
        bridgeLedger: [String: String] = [:],
        externalIDs: [String: String] = [:]
    ) {
        self.version = version
        self.plans = plans
        self.outcomes = outcomes
        self.bridgeLedger = bridgeLedger
        self.externalIDs = externalIDs
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
        change(&data)
        try writer(try Self.encoder.encode(data), fileURL)
    }

    // MARK: Plans

    public func plans(on day: Date) throws -> [PlanBlock] {
        let key = dayKey(day)
        return try load().plans.filter { dayKey($0.start) == key }
    }

    /// Replaces only `day`'s blocks. `externalIDs` maps Apple identifier -> external identifier.
    public func replacePlans(on day: Date, with blocks: [PlanBlock], externalIDs: [String: String] = [:]) throws {
        let key = dayKey(day)
        try update { data in
            data.plans.removeAll { dayKey($0.start) == key }
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
        let data = try load()
        let key = dayKey(day)
        if let hit = data.outcomes.first(where: { $0.key.identifier == identifier && $0.key.day == key }) {
            return hit.value
        }
        guard let externalID else { return nil }
        return data.outcomes.first(where: { $0.key.externalID == externalID && $0.key.day == key })?.value
    }

    /// Idempotent by (identifier, day); `nil` clears. Matches an existing mark by identifier or external id.
    public func setOutcome(_ record: EventOutcomeRecord?, for identifier: String, externalID: String?, on day: Date) throws {
        let key = dayKey(day)
        try update { data in
            let existing = data.outcomes.keys.filter {
                $0.day == key && ($0.identifier == identifier || (externalID != nil && $0.externalID == externalID))
            }
            for old in existing { data.outcomes[old] = nil }
            if let record {
                data.outcomes[OutcomeKey(identifier: identifier, externalID: externalID, day: key)] = record
            }
        }
    }

    // MARK: Bridge ledger

    public func recordBridge(itemID: String, identifier: String, externalID: String?) throws {
        try update { data in
            data.bridgeLedger[itemID] = identifier
            if let externalID { data.externalIDs[identifier] = externalID }
        }
    }

    public func bridgedIdentifier(for itemID: String) throws -> String? {
        try load().bridgeLedger[itemID]
    }

    // MARK: Identifier changes

    /// Rewrites every stored reference to `oldID` (plans, outcome keys, ledger, external-id map).
    /// Used when a re-match finds the item under a new identifier, and by phase 2.
    public func remap(oldID: String, newID: String) throws {
        try update { data in
            for i in data.plans.indices where data.plans[i].reminderID == oldID {
                data.plans[i].reminderID = newID
            }
            for key in data.outcomes.keys where key.identifier == oldID {
                var moved = key
                moved.identifier = newID
                data.outcomes[moved] = data.outcomes.removeValue(forKey: key)
            }
            for (item, id) in data.bridgeLedger where id == oldID { data.bridgeLedger[item] = newID }
            if let ext = data.externalIDs.removeValue(forKey: oldID) { data.externalIDs[newID] = ext }
        }
    }

    // MARK: Coding

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
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
