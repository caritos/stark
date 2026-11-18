// ios/Sources/StarkKit/Apple/CalendarSets.swift
import Foundation

/// A saved, named choice of calendars and reminder lists. Stores the INCLUDED ids, so a
/// calendar created after the set was saved is not in it.
public struct CalendarSet: Equatable, Hashable, Codable, Sendable, Identifiable {
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
    case emptyName, nameTooLong, duplicateName, noCalendars, notFound, everyCalendar, reservedName

    public var message: String {
        switch self {
        case .emptyName: return "Give the set a name."
        case .nameTooLong: return "Use 30 characters or fewer."
        case .duplicateName: return "Another set already has that name."
        case .noCalendars: return "Choose at least one calendar or list."
        case .notFound: return "That set no longer exists."
        case .everyCalendar: return "Untick at least one calendar, or use All Calendars."
        case .reservedName: return "That name is used by Stark. Pick another."
        }
    }
}

/// The saved sets, over `AppleSelection`. Applying a set writes an excluded-id selection, so
/// every screen keeps reading `AppleSelection`; the active set is derived, never stored.
public struct CalendarSets: Equatable, Sendable {
    public static let maxNameLength = 30
    static let currentVersion = 1
    /// The bar label uses these two words, so a set may not take them.
    static let reservedNames = ["Custom", "All Calendars"]

    public private(set) var sets: [CalendarSet]

    public init(sets: [CalendarSet] = []) {
        self.sets = sets
    }

    private func validated(_ name: String, excluding id: UUID?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw CalendarSetError.emptyName }
        if trimmed.count > Self.maxNameLength { throw CalendarSetError.nameTooLong }
        if Self.reservedNames.contains(where: { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            throw CalendarSetError.reservedName
        }
        let clash = sets.contains {
            $0.id != id && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
        if clash { throw CalendarSetError.duplicateName }
        return trimmed
    }

    /// With a loaded `allIDs` the ids are checked against it: ids that no longer exist do not
    /// count, so the set needs at least one that does, and it may not cover every calendar (that
    /// is All Calendars). `alwaysShown` ids (the default calendar and list) need not be ticked.
    private func checkIncluded(_ included: Set<String>, allIDs: Set<String>, alwaysShown: Set<String>) throws {
        if included.isEmpty { throw CalendarSetError.noCalendars }
        guard !allIDs.isEmpty else { return }
        if included.isDisjoint(with: allIDs) { throw CalendarSetError.noCalendars }
        if allIDs.subtracting(alwaysShown).isSubset(of: included) { throw CalendarSetError.everyCalendar }
    }

    @discardableResult
    public mutating func add(name: String, includedIDs: Set<String>, allIDs: Set<String> = [],
                             alwaysShown: Set<String> = [], id: UUID = UUID()) throws -> CalendarSet {
        let clean = try validated(name, excluding: nil)
        try checkIncluded(includedIDs, allIDs: allIDs, alwaysShown: alwaysShown)
        let set = CalendarSet(id: id, name: clean, includedIDs: includedIDs)
        sets.append(set)
        return set
    }

    public mutating func rename(_ id: UUID, to name: String) throws {
        guard let i = sets.firstIndex(where: { $0.id == id }) else { throw CalendarSetError.notFound }
        sets[i].name = try validated(name, excluding: id)
    }

    public mutating func updateIncluded(_ id: UUID, to ids: Set<String>, allIDs: Set<String> = [],
                                        alwaysShown: Set<String> = []) throws {
        guard let i = sets.firstIndex(where: { $0.id == id }) else { throw CalendarSetError.notFound }
        try checkIncluded(ids, allIDs: allIDs, alwaysShown: alwaysShown)
        sets[i].includedIDs = ids
    }

    public mutating func delete(_ id: UUID) {
        sets.removeAll { $0.id == id }
    }

    /// What a set hides: every calendar it does not include, except the always-shown ones (the
    /// default calendar and list are never hidden, so the selection never holds them).
    private func excluded(by set: CalendarSet, allIDs: Set<String>, alwaysShown: Set<String>) -> Set<String> {
        allIDs.subtracting(set.includedIDs).subtracting(alwaysShown)
    }

    private func currentExclusions(_ selection: AppleSelection, allIDs: Set<String>, alwaysShown: Set<String>) -> Set<String> {
        selection.excludedIDs.intersection(allIDs).subtracting(alwaysShown)
    }

    /// The selection that shows exactly this set's calendars (ids that no longer exist are ignored).
    public func selection(applying id: UUID, allIDs: Set<String>, alwaysShown: Set<String> = []) -> AppleSelection? {
        guard let set = sets.first(where: { $0.id == id }) else { return nil }
        return AppleSelection(excludedIDs: excluded(by: set, allIDs: allIDs, alwaysShown: alwaysShown))
    }

    /// Whether applying the set would show anything: at least one of its calendars still exists.
    /// A set whose calendars are all gone must be refused, or the agenda would be silently empty.
    public func canApply(_ id: UUID, allIDs: Set<String>) -> Bool {
        guard let set = sets.first(where: { $0.id == id }) else { return false }
        return !set.includedIDs.isDisjoint(with: allIDs)
    }

    /// The default calendar or list moved, and `keepShown` changed the selection under a set that
    /// was active: apply that set again for the new always-shown ids. nil when the set is gone,
    /// has no calendar left, or the selection already matches.
    public func reapplied(_ id: UUID, selection: AppleSelection, allIDs: Set<String>,
                          alwaysShown: Set<String>) -> AppleSelection? {
        guard canApply(id, allIDs: allIDs),
              let next = self.selection(applying: id, allIDs: allIDs, alwaysShown: alwaysShown),
              next != selection else { return nil }
        return next
    }

    /// The first set whose selection equals the current one; nil when nothing is excluded or
    /// the calendar list is not loaded yet (`allIDs` empty).
    public func activeSetID(for selection: AppleSelection, allIDs: Set<String>,
                            alwaysShown: Set<String> = []) -> UUID? {
        guard !allIDs.isEmpty else { return nil }
        let current = currentExclusions(selection, allIDs: allIDs, alwaysShown: alwaysShown)
        if current.isEmpty { return nil }
        return sets.first { excluded(by: $0, allIDs: allIDs, alwaysShown: alwaysShown) == current }?.id
    }

    /// "All Calendars", the active set's name or "Custom". Before the calendar list has loaded a
    /// hidden selection is "Calendars" (it may be a set, which cannot be told yet).
    public func label(for selection: AppleSelection, allIDs: Set<String>, alwaysShown: Set<String> = []) -> String {
        if allIDs.isEmpty { return selection.excludedIDs.isEmpty ? "All Calendars" : "Calendars" }
        if currentExclusions(selection, allIDs: allIDs, alwaysShown: alwaysShown).isEmpty { return "All Calendars" }
        if let id = activeSetID(for: selection, allIDs: allIDs, alwaysShown: alwaysShown),
           let set = sets.first(where: { $0.id == id }) {
            return set.name
        }
        return "Custom"
    }

    /// The calendar list changed while a set was active: the new calendars are not in the set, so
    /// they are hidden too and the set stays active. Only ever ADDS exclusions (a calendar that
    /// vanished for a moment and came back is hidden again, never un-hidden). nil when nothing
    /// is to change: no active set, no new calendar, or the first fetch (`previousAllIDs` empty).
    public func reconciled(selection: AppleSelection, previousAllIDs: Set<String>, newAllIDs: Set<String>,
                           alwaysShown: Set<String>) -> AppleSelection? {
        guard !previousAllIDs.isEmpty,
              let id = activeSetID(for: selection, allIDs: previousAllIDs, alwaysShown: alwaysShown),
              let set = sets.first(where: { $0.id == id }) else { return nil }
        let added = newAllIDs.subtracting(previousAllIDs).subtracting(set.includedIDs).subtracting(alwaysShown)
        if added.isSubset(of: selection.excludedIDs) { return nil }
        var next = selection
        next.excludedIDs.formUnion(added)
        return next
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
