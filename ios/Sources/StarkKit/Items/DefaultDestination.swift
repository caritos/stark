// ios/Sources/StarkKit/Items/DefaultDestination.swift
import Foundation

/// Where new Apple items go: the default calendar for events and the default list for reminders,
/// nil when none is chosen or available. The app's destination model conforms.
@MainActor
public protocol DefaultDestinations {
    var calendarID: String? { get }
    var listID: String? { get }
}

/// Which calendar new events go to and which list new reminders go to. The app's destination model
/// stores the chosen ids (ids only) and asks this for the effective one; pure so it is tested here.
public enum DefaultDestination {
    public struct Resolution: Equatable, Sendable {
        /// The calendar or list to use; nil when nothing writable exists.
        public let id: String?
        /// Store `id` as the choice (first use only; a stored choice is never overwritten).
        public let persist: Bool

        public init(id: String?, persist: Bool) {
            self.id = id
            self.persist = persist
        }
    }

    /// The writable calendars (or reminder lists) a picker offers, by title then id.
    public static func choices(_ calendars: [AppleCalendarInfo], reminderLists: Bool) -> [AppleCalendarInfo] {
        calendars
            .filter { $0.isWritable && $0.isReminderList == reminderLists }
            .sorted { lhs, rhs in
                let order = lhs.title.caseInsensitiveCompare(rhs.title)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
    }

    /// The stored choice when it is still a writable one; otherwise EventKit's default when that is
    /// writable, else the first writable one. Only a first use (nothing stored) persists the
    /// result: a stored choice that is missing right now (an account still syncing) is kept.
    public static func resolve(stored: String?, systemDefault: String?, in calendars: [AppleCalendarInfo],
                               reminderLists: Bool) -> Resolution {
        let writable = choices(calendars, reminderLists: reminderLists)
        if let stored, writable.contains(where: { $0.id == stored }) {
            return Resolution(id: stored, persist: false)
        }
        let fallback = writable.first { $0.id == systemDefault }?.id ?? writable.first?.id
        return Resolution(id: fallback, persist: stored == nil && fallback != nil)
    }

    /// The visible error when there is nowhere to add to; nil when both exist.
    public static func problem(calendarID: String?, listID: String?) -> String? {
        switch (calendarID, listID) {
        case (.some, .some):
            return nil
        case (nil, .some):
            return "No calendar Stark can add events to. Add or allow one in Apple Calendar, then choose it in Settings."
        case (.some, nil):
            return "No reminder list Stark can add to. Add one in Apple Reminders, then choose it in Settings."
        case (nil, nil):
            return "No calendar or reminder list Stark can add to. Add one in Apple Calendar or Reminders, then choose it in Settings."
        }
    }
}
