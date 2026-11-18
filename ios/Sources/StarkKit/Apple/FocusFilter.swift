// ios/Sources/StarkKit/Apple/FocusFilter.swift
import Foundation

/// What a Focus filter remembers while it has a calendar set applied: the excluded ids from
/// before the first Focus turned on (`before`) and the excluded ids it applied (`applied`), so
/// turning the Focus off can restore the first, unless the owner changed calendars meanwhile.
/// Device-only (UserDefaults `focusFilter.v1`).
public struct FocusFilterState: Codable, Equatable, Sendable {
    public var before: Set<String>
    public var applied: Set<String>

    public init(before: Set<String>, applied: Set<String>) {
        self.before = before
        self.applied = applied
    }

    static let currentVersion = 1

    private struct Envelope: Codable {
        var version: Int
        var before: [String]
        var applied: [String]
    }

    /// Missing, corrupt or newer-version data decodes to nil (never throws).
    public static func decode(_ data: Data?) -> FocusFilterState? {
        guard let data, let env = try? JSONDecoder().decode(Envelope.self, from: data),
              env.version == currentVersion else { return nil }
        return FocusFilterState(before: Set(env.before), applied: Set(env.applied))
    }

    public func encoded() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let env = Envelope(version: Self.currentVersion, before: before.sorted(), applied: applied.sorted())
        return (try? enc.encode(env)) ?? Data()
    }
}

/// The rules of the Focus filter, over excluded-id sets (`AppleSelection.excludedIDs`).
public enum FocusFilter {
    /// A Focus with a calendar set turned on. Applies the set exactly as the bar does and keeps
    /// the ORIGINAL `before` when a set is already applied by an earlier Focus. nil (change and
    /// remember nothing) for a deleted set, a set with no calendar left, or no calendars yet.
    public static func turnOn(setID: UUID, current: Set<String>, state: FocusFilterState?, sets: CalendarSets,
                              allIDs: Set<String>, alwaysShown: Set<String>)
        -> (selection: Set<String>, state: FocusFilterState)? {
        guard !allIDs.isEmpty, sets.canApply(setID, allIDs: allIDs),
              let next = sets.selection(applying: setID, allIDs: allIDs, alwaysShown: alwaysShown)
        else { return nil }
        let before = state?.before ?? current
        return (next.excludedIDs, FocusFilterState(before: before, applied: next.excludedIDs))
    }

    /// The Focus turned off (or its filter has no set): restore `before` when the selection is
    /// still what the Focus applied; a hand-changed selection is left (selection nil). The
    /// memory is always forgotten (state nil).
    public static func turnOff(current: Set<String>, state: FocusFilterState?)
        -> (selection: Set<String>?, state: FocusFilterState?) {
        guard let state, current == state.applied else { return (nil, nil) }
        return (state.before, nil)
    }
}
