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
/// still happens. This matters because `EditItemView`'s actions (Done, Remove This Occurrence)
/// write to whatever occurrence date the `AgendaItem` they were opened from carries
/// (`ItemRouter.complete(id:on:)` and friends) -- passing the anchor would act on an occurrence
/// that may be years in the past, with no visible effect in the agenda (a non-recurring item's
/// anchor already *is* its only occurrence, so it's unaffected).
public enum SearchResults {
    /// How far to look for a recurring series' occurrences around `today`. Generous enough for
    /// any realistic recurrence (a task app's items don't recur for centuries), and bounded so a
    /// pathological rule can't make this an unbounded scan.
    private static let occurrenceWindowDays = 3650

    /// `apple` (default empty) adds the Apple items: one row per reminder and one per EVENT SERIES
    /// (`representativeAppleEvents`, the nearest occurrence at or after `today`, else the latest), dated by the item's own date (a
    /// date-only reminder at local midnight, an undated reminder at `.distantPast`), with the same
    /// ids and `AppleSource` as the agenda (`appleReminderValue`). The engine applies NO window of
    /// its own to Apple items: every event and reminder in `apple` is searched, completed and
    /// undated reminders included. The caller passes a snapshot of events within two years either
    /// side of today and ALL reminders (spec Decision 10), not the agenda's display snapshot.
    public static func find(events: [Event], reminders: [Reminder], apple: AppleSnapshot = AppleSnapshot(events: [], reminders: []), query: String, today: Date = Date()) -> [AgendaItem] {
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

        let calendar = Calendar(identifier: .gregorian)
        // Match first, then collapse each series to one row (a detached occurrence with its own
        // title still counts on its own match).
        let matching = apple.events.filter {
            contains($0.title, query) || contains($0.notes, query) || contains($0.location, query)
        }
        for item in representativeAppleEvents(matching, today: today) {
            let event = Event(id: "apple-\(item.id)", title: item.title, notes: item.notes, start: item.start, end: item.end,
                              isAllDay: item.isAllDay, location: item.location, url: item.url)
            let source = AppleSource(calendarID: item.calendar.id, calendarTitle: item.calendar.title,
                                     colorHex: item.calendar.colorHex, isReminder: false,
                                     isWritable: item.calendar.isWritable)
            results.append(AgendaItem(kind: .event(event), occurrence: item.start, displayDate: item.start, isOverdue: false, appleSource: source))
        }
        for item in apple.reminders {
            let (reminder, source) = appleReminderValue(item, calendar: calendar)
            guard matches(reminder, query: query) else { continue }
            let date = reminder.dueDate ?? .distantPast
            results.append(AgendaItem(kind: .reminder(reminder), occurrence: date, displayDate: date, isOverdue: false, appleSource: source))
        }

        // Newest date first (issue raised as "sort by most recent created" -- there is no
        // creation timestamp anywhere in the model or the .ics format, so this sorts by each
        // item's own date instead, descending).
        return results.sorted { $0.displayDate > $1.displayDate }
    }

    /// One Apple event per series, as for Stark's own recurring items: occurrences sharing an
    /// identifier (a detached one adds `/RID=<n>` to it) collapse to the soonest at or after
    /// `today`, else the latest. The caller passes only the matching occurrences.
    static func representativeAppleEvents(_ events: [AppleCalendarEvent], today: Date) -> [AppleCalendarEvent] {
        var bySeries: [String: [AppleCalendarEvent]] = [:]
        var order: [String] = []
        for event in events {
            let series = event.id.range(of: "/RID=").map { String(event.id[..<$0.lowerBound]) } ?? event.id
            if bySeries[series] == nil { order.append(series) }
            bySeries[series, default: []].append(event)
        }
        return order.compactMap { series in
            let occurrences = bySeries[series] ?? []
            return occurrences.filter { $0.start >= today }.min { $0.start < $1.start }
                ?? occurrences.max { $0.start < $1.start }
        }
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
