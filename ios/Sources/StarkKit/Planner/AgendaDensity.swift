// ios/Sources/StarkKit/Planner/AgendaDensity.swift
import Foundation

/// How many task and event rows fall on one calendar day. Raw counts: the month grid decides how
/// many markers to draw (it caps them), this never does.
public struct DayDensity: Equatable, Sendable {
    public var tasks: Int
    public var events: Int

    public init(tasks: Int, events: Int) {
        self.tasks = tasks
        self.events = events
    }

    /// A day with nothing on it. `dayDensity` never stores these; the view falls back to it.
    public static let none = DayDensity(tasks: 0, events: 0)

    /// What VoiceOver reads for a month-grid day cell: the day number, "today" when it is, then
    /// the task and event counts (omitted when zero), e.g. "20, today, 3 tasks, 1 event".
    public func accessibilityLabel(day: Int, isToday: Bool) -> String {
        accessibilityLabel(title: "\(day)", isToday: isToday)
    }

    /// The same label with `title` (for example "Oct 1" for a neighbouring-month cell) in place
    /// of the bare day number, e.g. "Oct 1, today, 3 tasks, 1 event".
    public func accessibilityLabel(title: String, isToday: Bool) -> String {
        var parts = [title]
        if isToday { parts.append("today") }
        if tasks > 0 { parts.append("\(tasks) \(tasks == 1 ? "task" : "tasks")") }
        if events > 0 { parts.append("\(events) \(events == 1 ? "event" : "events")") }
        return parts.joined(separator: ", ")
    }
}

/// Per-day task/event counts for one whole month, for the month grid's density markers.
///
/// Built on `buildAgendaItems` — over the month's full range — so the grid can never disagree
/// with the agenda about what is on a day. A reminder row (incomplete, completed, or
/// overdue-pinned) counts as a task and an event row as an event. Consequently an overdue
/// reminder counts on **today's** day (its `displayDate`), not its missed date, and only when
/// today falls inside `month`; completed reminders count on their due date.
///
/// Works for any month, not just the agenda's display window: the range is the month itself.
/// (An incomplete reminder in a month wholly before `today` has, exactly as in the agenda, become
/// overdue and moved to today, so it is not counted on its old day.)
///
/// Returns a dictionary keyed by day of month (1...31) holding only days with something on them,
/// so an empty month is `[:]`. A dictionary rather than a dense array because most days of a
/// typical month are empty, and callers look days up by number either way.
///
/// The month's bounds and the day-of-month keys come from `calendar`; the whole day is covered
/// (start of day 1 through the last second of the last day) and days are stepped with the
/// calendar, never by 86 400 seconds, so 23- and 25-hour DST days key correctly. Note that
/// `buildAgendaItems` and `OccurrenceExpander` expand in the process's current time zone, so
/// `calendar` should share it for recurring events and overdue detection to line up (as it does
/// by default).
public func dayDensity(
    events: [Event],
    reminders: [Reminder],
    month: YearMonth,
    today: Date = Date(),
    calendar: Calendar = Calendar(identifier: .gregorian)
) -> [Int: DayDensity] {
    guard let firstDay = calendar.date(from: DateComponents(year: month.year, month: month.month0 + 1, day: 1)),
          let firstOfNext = calendar.date(byAdding: .month, value: 1, to: firstDay) else { return [:] }
    let start = calendar.startOfDay(for: firstDay)
    let range = start...calendar.startOfDay(for: firstOfNext).addingTimeInterval(-1)

    var result: [Int: DayDensity] = [:]
    for item in buildAgendaItems(events: events, reminders: reminders, in: range, today: today) {
        // buildAgendaItems can also return rows pinned to today (overdue) when today is outside
        // this month; they belong to another month's cell.
        guard range.contains(item.displayDate) else { continue }
        let day = calendar.component(.day, from: item.displayDate)
        switch item.kind {
        case .event: result[day, default: .none].events += 1
        case .reminder: result[day, default: .none].tasks += 1
        }
    }
    return result
}

/// Per-day task/event counts for every cell of `month`'s grid — the month itself plus the
/// neighbouring months' leading/trailing days — keyed by ISO date (`yyyy-MM-dd`).
///
/// Same rules as `dayDensity` (it is built on `buildAgendaItems` over the whole grid range so the
/// grid can never disagree with the agenda): an overdue reminder counts on **today's** cell, and
/// only when today falls inside the grid range. Only days with something on them are stored.
public func gridDensity(
    events: [Event],
    reminders: [Reminder],
    month: YearMonth,
    today: Date = Date(),
    calendar: Calendar = Calendar(identifier: .gregorian)
) -> [String: DayDensity] {
    let range = MonthGrid.range(for: month, calendar: calendar)

    var result: [String: DayDensity] = [:]
    for item in buildAgendaItems(events: events, reminders: reminders, in: range, today: today) {
        // buildAgendaItems can also return rows pinned to today (overdue) when today is outside
        // the range; they belong to a cell that is not on this grid.
        guard range.contains(item.displayDate) else { continue }
        let c = calendar.dateComponents([.year, .month, .day], from: item.displayDate)
        guard let year = c.year, let month = c.month, let day = c.day else { continue }
        let iso = DateMath.isoDate(year: year, month0: month - 1, day: day)
        switch item.kind {
        case .event: result[iso, default: .none].events += 1
        case .reminder: result[iso, default: .none].tasks += 1
        }
    }
    return result
}
