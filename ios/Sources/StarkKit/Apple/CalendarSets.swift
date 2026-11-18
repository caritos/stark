// ios/Sources/StarkKit/Apple/CalendarSets.swift
import Foundation

/// A saved, named choice of calendars and reminder lists. Stores the INCLUDED ids, so a
/// calendar created after the set was saved is not in it.
public struct CalendarSet: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var includedIDs: Set<String>

    public init(id: UUID = UUID(), name: String, includedIDs: Set<String>) {
        self.id = id
        self.name = name
        self.includedIDs = includedIDs
    }
}

public enum CalendarSetError: Error, Equatable, Sendable {
    case emptyName, nameTooLong, duplicateName, noCalendars, notFound

    public var message: String {
        switch self {
        case .emptyName: return "Give the set a name."
        case .nameTooLong: return "Use 30 characters or fewer."
        case .duplicateName: return "Another set already has that name."
        case .noCalendars: return "Choose at least one calendar or list."
        case .notFound: return "That set no longer exists."
        }
    }
}

/// The saved sets, over `AppleSelection`. Applying a set writes an excluded-id selection, so
/// every screen keeps reading `AppleSelection`; the active set is derived, never stored.
public struct CalendarSets: Equatable, Sendable {
    public static let maxNameLength = 30
    static let currentVersion = 1

    public private(set) var sets: [CalendarSet]

    public init(sets: [CalendarSet] = []) {
        self.sets = sets
    }

    private func validated(_ name: String, excluding id: UUID?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw CalendarSetError.emptyName }
        if trimmed.count > Self.maxNameLength { throw CalendarSetError.nameTooLong }
        let clash = sets.contains {
            $0.id != id && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
        if clash { throw CalendarSetError.duplicateName }
        return trimmed
    }

    @discardableResult
    public mutating func add(name: String, includedIDs: Set<String>, id: UUID = UUID()) throws -> CalendarSet {
        let clean = try validated(name, excluding: nil)
        if includedIDs.isEmpty { throw CalendarSetError.noCalendars }
        let set = CalendarSet(id: id, name: clean, includedIDs: includedIDs)
        sets.append(set)
        return set
    }

    public mutating func rename(_ id: UUID, to name: String) throws {
        guard let i = sets.firstIndex(where: { $0.id == id }) else { throw CalendarSetError.notFound }
        sets[i].name = try validated(name, excluding: id)
    }

    public mutating func updateIncluded(_ id: UUID, to ids: Set<String>) throws {
        guard let i = sets.firstIndex(where: { $0.id == id }) else { throw CalendarSetError.notFound }
        if ids.isEmpty { throw CalendarSetError.noCalendars }
        sets[i].includedIDs = ids
    }

    public mutating func delete(_ id: UUID) {
        sets.removeAll { $0.id == id }
    }

    private func excluded(by set: CalendarSet, allIDs: Set<String>) -> Set<String> {
        allIDs.subtracting(set.includedIDs)
    }

    /// The selection that shows exactly this set's calendars (ids that no longer exist are ignored).
    public func selection(applying id: UUID, allIDs: Set<String>) -> AppleSelection? {
        guard let set = sets.first(where: { $0.id == id }) else { return nil }
        return AppleSelection(excludedIDs: excluded(by: set, allIDs: allIDs))
    }

    /// The first set whose selection equals the current one; nil when nothing is excluded.
    public func activeSetID(for selection: AppleSelection, allIDs: Set<String>) -> UUID? {
        let current = selection.excludedIDs.intersection(allIDs)
        if current.isEmpty { return nil }
        return sets.first { excluded(by: $0, allIDs: allIDs) == current }?.id
    }

    public func label(for selection: AppleSelection, allIDs: Set<String>) -> String {
        if selection.excludedIDs.intersection(allIDs).isEmpty { return "All Calendars" }
        if let id = activeSetID(for: selection, allIDs: allIDs),
           let set = sets.first(where: { $0.id == id }) {
            return set.name
        }
        return "Custom"
    }

    private struct Envelope: Codable {
        var version: Int
        var sets: [CalendarSet]
    }

    private struct VersionOnly: Decodable {
        var version: Int
    }

    /// Missing, corrupt or newer-version data decodes to no sets (never throws, never crashes).
    public static func decode(_ data: Data?) -> CalendarSets {
        guard let data,
              let v = try? JSONDecoder().decode(VersionOnly.self, from: data),
              v.version == currentVersion,
              let env = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return CalendarSets() }
        return CalendarSets(sets: env.sets)
    }

    public func encoded() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(Envelope(version: Self.currentVersion, sets: sets))) ?? Data()
    }
}
