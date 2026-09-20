// ios/Sources/StarkKit/Planner/AgendaBuilder.swift
import Foundation

/// One row of the agenda: a dated occurrence of an event or reminder.
public struct AgendaItem: Identifiable, Equatable {
    public enum Kind: Equatable {
        case event(Event)
        case reminder(Reminder)
    }

    public let kind: Kind
    /// The real scheduled occurrence. This is what Done / Skip / Undo act on.
    public let occurrence: Date
    /// Where the row sits in the list. Equal to `occurrence` unless the row is overdue-pinned.
    public let displayDate: Date
    /// True when `displayDate` is start-of-today and `occurrence` is the missed date.
    public let isOverdue: Bool

    public init(kind: Kind, occurrence: Date, displayDate: Date, isOverdue: Bool) {
        self.kind = kind
        self.occurrence = occurrence
        self.displayDate = displayDate
        self.isOverdue = isOverdue
    }

    public var id: String {
        switch kind {
        case .event(let event): return "\(event.id)-\(occurrence.timeIntervalSince1970)"
        case .reminder(let reminder): return "\(reminder.id)-\(occurrence.timeIntervalSince1970)"
        }
    }

    public var title: String {
        switch kind {
        case .event(let event): return event.title
        case .reminder(let reminder): return reminder.title
        }
    }

    /// Reminders only; events are never completed.
    public var isCompleted: Bool {
        switch kind {
        case .event: return false
        case .reminder(let reminder): return reminder.isCompleted
        }
    }

    public var isRecurring: Bool {
        switch kind {
        case .event(let event): return event.recurrence != nil
        case .reminder(let reminder): return reminder.recurrence != nil
        }
    }

    /// Events only: what the user recorded for *this* occurrence (matched by calendar day), or nil
    /// when nothing is recorded. Always nil for reminders. Derived, so it can never disagree with
    /// the event it came from.
    public var outcome: EventOutcome? {
        guard case .event(let event) = kind else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        return event.outcomes.first { calendar.isDate($0.date, inSameDayAs: occurrence) }?.outcome
    }
}

/// Expands every event/reminder into concrete dated agenda rows and sorts them. The single
/// source of truth `AgendaView` and `MonthGridView` build on — never duplicate this in a view.
///
/// - Events expand within `displayRange` only and are never overdue.
/// - Completed reminders (always one-offs) appear at their `dueDate` when it is inside
///   `displayRange`; never overdue.
/// - Incomplete reminders also expand `overdueLookbackDays` back from today. Occurrences before
///   today are overdue and pinned to start-of-today (`displayDate`), keeping the missed date in
///   `occurrence`. A non-recurring reminder is pinned as-is; a weekly/monthly/yearly one keeps
///   only its most recent missed occurrence; a daily one drops missed occurrences entirely (a
///   missed daily occurrence isn't meaningful, and pinning it would nag every day).
///   Occurrences already skipped/completed are excluded by `OccurrenceExpander`'s exception dates.
///
/// "Overdue" is day-granular: an occurrence is overdue iff its day is before today's day.
///
/// Sorted by day of `displayDate`; within a day: overdue (by `occurrence`), then normal
/// incomplete/event items (by `displayDate`), then completed items (by `displayDate`); ties
/// break on `id`, making the order total and deterministic.
public func buildAgendaItems(
    events: [Event],
    reminders: [Reminder],
    in displayRange: ClosedRange<Date>,
    today: Date = Date(),
    overdueLookbackDays: Int = AgendaWindow.overdueLookbackDays
) -> [AgendaItem] {
    let calendar = Calendar(identifier: .gregorian)
    let todayStart = calendar.startOfDay(for: today)
    let lookbackStart = calendar.date(byAdding: .day, value: -overdueLookbackDays, to: todayStart) ?? todayStart
    let reminderRange = min(displayRange.lowerBound, lookbackStart)...displayRange.upperBound

    var items: [AgendaItem] = []

    for event in events {
        for occurrence in OccurrenceExpander.expand(event: event, in: displayRange) {
            items.append(AgendaItem(kind: .event(event), occurrence: occurrence, displayDate: occurrence, isOverdue: false))
        }
    }

    for reminder in reminders {
        if reminder.isCompleted {
            if let due = reminder.dueDate, displayRange.contains(due) {
                items.append(AgendaItem(kind: .reminder(reminder), occurrence: due, displayDate: due, isOverdue: false))
            }
            continue
        }

        var missed: [Date] = []
        for occurrence in OccurrenceExpander.expand(reminder: reminder, in: reminderRange) {
            if calendar.startOfDay(for: occurrence) < todayStart {
                missed.append(occurrence)
            } else if displayRange.contains(occurrence) {
                items.append(AgendaItem(kind: .reminder(reminder), occurrence: occurrence, displayDate: occurrence, isOverdue: false))
            }
        }

        let overdueOccurrences: [Date]
        switch reminder.recurrence?.frequency {
        case nil: overdueOccurrences = missed
        case .daily: overdueOccurrences = []
        case .weekly, .monthly, .yearly: overdueOccurrences = missed.max().map { [$0] } ?? []
        }
        for occurrence in overdueOccurrences {
            items.append(AgendaItem(kind: .reminder(reminder), occurrence: occurrence, displayDate: todayStart, isOverdue: true))
        }
    }

    return items.sorted { lhs, rhs in
        let lhsDay = calendar.startOfDay(for: lhs.displayDate)
        let rhsDay = calendar.startOfDay(for: rhs.displayDate)
        if lhsDay != rhsDay { return lhsDay < rhsDay }

        let lhsGroup = sortGroup(lhs)
        let rhsGroup = sortGroup(rhs)
        if lhsGroup != rhsGroup { return lhsGroup < rhsGroup }

        // Overdue rows all share a displayDate, so their real order is the missed occurrence.
        let lhsKey = lhs.isOverdue ? lhs.occurrence : lhs.displayDate
        let rhsKey = rhs.isOverdue ? rhs.occurrence : rhs.displayDate
        if lhsKey != rhsKey { return lhsKey < rhsKey }

        return lhs.id < rhs.id
    }
}

/// 0 = overdue, 1 = normal incomplete/event, 2 = completed.
private func sortGroup(_ item: AgendaItem) -> Int {
    if item.isOverdue { return 0 }
    if item.isCompleted { return 2 }
    return 1
}
