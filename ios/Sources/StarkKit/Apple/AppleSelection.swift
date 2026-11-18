// ios/Sources/StarkKit/Apple/AppleSelection.swift
import Foundation

/// Which Apple calendars and reminder lists the overlay shows. Stored as the set of EXCLUDED
/// ids so an empty set means "everything on" and a calendar created later appears by itself.
/// Persistence (a plain `Set<String>`) is the app layer's job.
public struct AppleSelection: Equatable, Sendable {
    public var excludedIDs: Set<String>

    public init(excludedIDs: Set<String> = []) {
        self.excludedIDs = excludedIDs
    }

    public func isShown(_ calendarID: String) -> Bool {
        !excludedIDs.contains(calendarID)
    }

    /// Drops excluded ids whose calendar no longer exists.
    public func pruned(toExisting ids: Set<String>) -> AppleSelection {
        AppleSelection(excludedIDs: excludedIDs.intersection(ids))
    }

    public func filtered(_ snapshot: AppleSnapshot) -> AppleSnapshot {
        AppleSnapshot(
            events: snapshot.events.filter { isShown($0.calendar.id) },
            reminders: snapshot.reminders.filter { isShown($0.calendar.id) },
            birthYears: snapshot.birthYears)
    }
}
