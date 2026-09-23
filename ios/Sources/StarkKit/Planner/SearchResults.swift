// ios/Sources/StarkKit/Planner/SearchResults.swift
import Foundation

/// Full-history text search over stored events and reminders (their master records, not
/// expanded agenda occurrences) — see `SearchView` in the app layer, which is a thin wrapper
/// around this.
///
/// One unconditional case-insensitive substring match across title, notes, and location
/// (events) or title and notes (reminders) — no field picker (a Fantastical-style
/// Title/Notes/Location/All row was considered and dropped for simplicity, see
/// `docs/superpowers/specs/2026-09-23-native-search-design.md`).
///
/// For a **recurring** item, the returned `AgendaItem.occurrence` is a real scheduled
/// occurrence -- the next upcoming one relative to `today`, or the most recent past one if the
/// series has none left -- never the raw stored anchor (`Event.start`/`Reminder.dueDate`),
/// which for a recurring item is only the series' first occurrence, not necessarily one that
/// still happens. This matters because `EditItemView`'s actions (Done, Skip This Occurrence,
/// Attended/Didn't Attend) all write to whatever occurrence date the `AgendaItem` they were
/// opened from carries (`PlannerStore.completeReminder(id:on:)` and friends) -- passing the
/// anchor would silently exdate and file a completed copy against a occurrence that may be
/// years in the past, with no visible effect in the agenda (found in the final review of this
/// feature; a non-recurring item's anchor already *is* its only occurrence, so it's unaffected).
public enum SearchResults {
    /// How far to look for a recurring series' occurrences around `today`. Generous enough for
    /// any realistic recurrence (a task app's items don't recur for centuries), and bounded so a
    /// pathological rule can't make this an unbounded scan.
    private static let occurrenceWindowDays = 3650

    public static func find(events: [Event], reminders: [Reminder], query: String, today: Date = Date()) -> [AgendaItem] {
        guard !query.isEmpty else { return [] }
        var results: [AgendaItem] = []

        for event in events where matches(event, query: query) {
            let occurrence = representativeOccurrence(event: event, today: today)
            results.append(AgendaItem(kind: .event(event), occurrence: occurrence, displayDate: occurrence, isOverdue: false))
        }
        for reminder in reminders where matches(reminder, query: query) {
            let occurrence = representativeOccurrence(reminder: reminder, today: today)
            results.append(AgendaItem(kind: .reminder(reminder), occurrence: occurrence, displayDate: occurrence, isOverdue: false))
        }

        // Newest date first (issue raised as "sort by most recent created" -- there is no
        // creation timestamp anywhere in the model or the .ics format, so this sorts by each
        // item's own date instead, descending).
        return results.sorted { $0.displayDate > $1.displayDate }
    }

    private static func representativeOccurrence(event: Event, today: Date) -> Date {
        guard event.recurrence != nil else { return event.start }
        let candidates = OccurrenceExpander.expand(event: event, in: searchWindow(around: today))
        return nearestOccurrence(candidates, today: today) ?? event.start
    }

    /// `.distantPast` for an undated reminder (rather than `Date()`), so it sorts to the very
    /// end of the (newest-first) results -- stable across recomputation, unlike "now", which
    /// would also make the row's `AgendaItem.id` (which embeds the occurrence's timestamp)
    /// change on every keystroke.
    private static func representativeOccurrence(reminder: Reminder, today: Date) -> Date {
        guard let dueDate = reminder.dueDate else { return .distantPast }
        guard reminder.recurrence != nil else { return dueDate }
        let candidates = OccurrenceExpander.expand(reminder: reminder, in: searchWindow(around: today))
        return nearestOccurrence(candidates, today: today) ?? dueDate
    }

    private static func searchWindow(around today: Date) -> ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        let lower = calendar.date(byAdding: .day, value: -occurrenceWindowDays, to: today) ?? today
        let upper = calendar.date(byAdding: .day, value: occurrenceWindowDays, to: today) ?? today
        return lower...upper
    }

    /// The soonest occurrence at or after `today`, or the most recent one before it if none
    /// remain (e.g. the series' `recur-until` already passed).
    private static func nearestOccurrence(_ candidates: [Date], today: Date) -> Date? {
        candidates.filter { $0 >= today }.min() ?? candidates.max()
    }

    private static func matches(_ event: Event, query: String) -> Bool {
        contains(event.title, query) || contains(event.notes, query) || contains(event.location, query)
    }

    private static func matches(_ reminder: Reminder, query: String) -> Bool {
        contains(reminder.title, query) || contains(reminder.notes, query)
    }

    /// `.range(of:options:)` avoids allocating a lowercased copy of every field on every call
    /// (this runs once per keystroke over the user's whole history -- a real dataset in this
    /// project has run to 8,000+ lines/items).
    private static func contains(_ haystack: String?, _ query: String) -> Bool {
        guard let haystack, !query.isEmpty else { return false }
        return haystack.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
