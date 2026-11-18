// ios/Sources/StarkKit/Apple/BirthYear.swift
import Foundation

public enum BirthYear {
    /// The birth year in a contact's birthday components; nil without components or a year, and for
    /// years before 1900 (Contacts stores a placeholder year such as 1604 when none was entered).
    public static func year(from components: DateComponents?) -> Int? {
        guard let year = components?.year, year >= 1900 else { return nil }
        return year
    }

    /// Contact ids of the Birthdays calendar's events. Empty means Contacts must not be touched.
    public static func contactIDsNeeded(in events: [AppleCalendarEvent]) -> Set<String> {
        Set(events.compactMap { $0.calendar.isBirthdayCalendar ? $0.birthdayContactID : nil })
    }
}

/// Looks up birth years in Contacts. Returns `[:]` when access is missing; never throws.
public protocol BirthYearLookup: Sendable {
    func birthYears(forContactIDs ids: Set<String>) async -> [String: Int]
}

/// Birth years already read from Contacts, per contact id, for the overlay model's lifetime (in
/// memory only, never persisted). A contact with no year is remembered as such, so reloads and
/// `EKEventStoreChanged` bursts do not re-read Contacts. Only one lookup runs at a time: a second
/// `load` waits for the first and then asks only for what is still unknown, so two overlapping
/// reloads can never both show the Contacts prompt.
@MainActor
public final class BirthYearCache {
    private let lookup: BirthYearLookup
    /// nil value: asked, no year (or no access at the time).
    private var known: [String: Int?] = [:]
    private var inFlight: Task<Bool, Never>?

    public init(lookup: BirthYearLookup) {
        self.lookup = lookup
    }

    /// The cached years among `ids` (ids without a known year are absent).
    public func years(for ids: Set<String>) -> [String: Int] {
        var result: [String: Int] = [:]
        for id in ids {
            if let entry = known[id], let year = entry { result[id] = year }
        }
        return result
    }

    /// The ids among `ids` never asked for.
    public func missing(from ids: Set<String>) -> Set<String> {
        ids.filter { known[$0] == nil }
    }

    /// Looks up the ids not yet known (off the main actor). Returns whether a new year was learned.
    public func load(_ ids: Set<String>) async -> Bool {
        while let running = inFlight {
            _ = await running.value
        }
        let ask = missing(from: ids)
        guard !ask.isEmpty else { return false }
        let lookup = self.lookup
        // The task clears `inFlight` itself before it finishes, so a waiter that resumes never
        // finds the finished task still there (awaiting it again would not suspend: a spin).
        let task = Task { @MainActor [weak self] () -> Bool in
            let found = await Task.detached { await lookup.birthYears(forContactIDs: ask) }.value
            guard let self else { return false }
            for id in ask {
                self.known[id] = .some(found[id])
            }
            self.inFlight = nil
            return !found.isEmpty
        }
        inFlight = task
        return await task.value
    }

    /// Forgets the ids that had no year, so they are asked again (the owner may have granted
    /// Contacts access or added a year in the meantime). Called when the app comes to the front.
    public func forgetMissing() {
        known = known.filter { $0.value != nil }
    }
}
