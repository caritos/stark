// ios/Sources/StarkKit/Apple/FocusFilter.swift
import Foundation

/// What a Focus filter remembers while it has a calendar set applied: the excluded ids from
/// before the first Focus turned on (`before`) and the excluded ids it applied (`applied`), so
/// turning the Focus off can restore the first, unless the owner changed calendars meanwhile.
/// Device-only (UserDefaults `focusFilter.v1`).
public struct FocusFilterState: Codable, Equatable, Sendable {
    public var before: Set<String>
    public var applied: Set<String>
    /// The set that was applied: turning off also recognises the selection as the Focus's when
    /// the app adjusted it (a new calendar hidden with the set), not only when it is identical.
    public var setID: UUID?

    public init(before: Set<String>, applied: Set<String>, setID: UUID? = nil) {
        self.before = before
        self.applied = applied
        self.setID = setID
    }

    static let currentVersion = 1

    private struct Envelope: Codable {
        var version: Int
        var before: [String]
        var applied: [String]
        var setID: UUID?
    }

    /// Missing, corrupt or newer-version data decodes to nil (never throws).
    public static func decode(_ data: Data?) -> FocusFilterState? {
        guard let data, let env = try? JSONDecoder().decode(Envelope.self, from: data),
              env.version == currentVersion else { return nil }
        return FocusFilterState(before: Set(env.before), applied: Set(env.applied), setID: env.setID)
    }

    public func encoded() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let env = Envelope(version: Self.currentVersion, before: before.sorted(), applied: applied.sorted(), setID: setID)
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
        return (next.excludedIDs, FocusFilterState(before: before, applied: next.excludedIDs, setID: setID))
    }

    /// The Focus turned off (or its filter has no set): restore `before` when the selection is
    /// still the Focus's, either exactly what it applied or, after the app adjusted it itself
    /// (a new calendar hidden with the set, the default moving), still the same set; a
    /// hand-changed selection is left (selection nil). The memory is always forgotten (state nil).
    public static func turnOff(current: Set<String>, state: FocusFilterState?, sets: CalendarSets = CalendarSets(),
                               allIDs: Set<String> = [], alwaysShown: Set<String> = [])
        -> (selection: Set<String>?, state: FocusFilterState?) {
        guard let state else { return (nil, nil) }
        if current == state.applied { return (state.before, nil) }
        if let setID = state.setID,
           sets.activeSetID(for: AppleSelection(excludedIDs: current), allIDs: allIDs, alwaysShown: alwaysShown) == setID {
            return (state.before, nil)
        }
        return (nil, nil)
    }
}
