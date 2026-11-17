// ios/Sources/StarkKit/Planner/WeeklyReview.swift
import Foundation

/// A Sunday-to-Saturday look back (or ahead) at what got done and what is still open.
///
/// Built on `buildAgendaItems` (the single source of truth for what the agenda shows) and bucketed
/// by each item's real `occurrence`, never the overdue-pinned `displayDate`: a reminder missed on
/// Tuesday is still open for *Tuesday's* week.
///
/// Known limitations:
/// - "Completed this week" means *due* that week (bucketed by occurrence date, deliberately, even
///   though `completedAt` now records when it was ticked).
/// - A recurring series (daily included) has ONE open row carrying its first unresolved miss, so it
///   is bucketed into the week of that first miss, not the later weeks it was carried through.
/// - For weeks older than the 90-day lookback an open row can appear for that week's first miss;
///   resolving it clears only that occurrence (`PlannerStore` bounds clearing by the lookback).
public struct WeeklyReview: Equatable {
    /// Start of the week's Sunday.
    public let weekStart: Date
    /// Start of Sunday through the last second of Saturday.
    public let range: ClosedRange<Date>
    /// Completed reminders due in the week (Apple ones: completed in the week), by occurrence.
    public let completed: [AgendaItem]
    /// Incomplete reminders whose (possibly missed) occurrence is in the week, by occurrence.
    /// Events add nothing (phase 3, spec decision 3: the attended count was always 0 for Apple
    /// events, whose marks live in the sidecar and show in the editor only).
    public let open: [AgendaItem]

    /// e.g. "14 done · 3 open".
    public var countsLabel: String { "\(completed.count) done · \(open.count) open" }

    /// The review as plain text, for pasting into a note or another tool (issue #111): ISO dates so
    /// it parses cleanly, the same counts as the screen, then the completed and still-open lists
    /// (titles only, by occurrence date).
    public func shareText(calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        func day(_ date: Date) -> String {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return DateMath.isoDate(year: c.year!, month0: c.month! - 1, day: c.day!)
        }
        func lines(_ items: [AgendaItem]) -> String {
            items.isEmpty ? "- (none)" : items.map { "- \(day($0.occurrence)) \($0.title)" }.joined(separator: "\n")
        }
        return """
        Weekly Review: \(day(weekStart)) to \(day(range.upperBound))
        \(countsLabel)

        Completed
        \(lines(completed))

        Still open
        \(lines(open))
        """
    }

    /// The week to open on: last week on a Monday (reviewing the week just ended), otherwise the
    /// current one. Returned as the start of that week's Sunday.
    public static func defaultWeekStart(today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        let day = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: day) // 1 = Sunday ... 7 = Saturday
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: day)!
        let start = weekday == 2 ? calendar.date(byAdding: .day, value: -7, to: sunday)! : sunday
        return calendar.startOfDay(for: start)
    }

    public static func weekStart(after weekStart: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: 7, to: weekStart)!)
    }

    public static func weekStart(before weekStart: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: -7, to: weekStart)!)
    }

    /// The start of `weekStart`'s day through the last second of the Saturday six days later.
    /// Stepped with the calendar so a 23- or 25-hour DST day still lands on the right midnight.
    public static func range(forWeekStarting weekStart: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> ClosedRange<Date> {
        let first = calendar.startOfDay(for: weekStart)
        let dayAfterLast = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 7, to: first)!)
        return first...dayAfterLast.addingTimeInterval(-1)
    }

    /// What `PlannerStore.loadMonths(covering:)` must read before `summary` is meaningful: the
    /// week, widened back to the overdue lookback from `today` (otherwise overdue reminders in
    /// unloaded month files silently vanish).
    public static func loadRange(
        forWeekStarting weekStart: Date,
        today: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> ClosedRange<Date> {
        let week = range(forWeekStarting: weekStart, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        let lookbackStart = calendar.date(byAdding: .day, value: -AgendaWindow.overdueLookbackDays, to: todayStart) ?? todayStart
        return min(week.lowerBound, lookbackStart)...week.upperBound
    }

    /// `apple` (default empty: local behaviour unchanged) adds Apple reminders, read only from
    /// what Apple keeps (spec Decision 1, spike (a)):
    /// - a completed Apple reminder counts in the week of its COMPLETION date (`completedAt`, or
    ///   its due date when Apple gave none), and that is its row's `occurrence`. Apple leaves a
    ///   completed copy per completion of a repeating reminder, so those count like one-offs;
    /// - an open dated Apple reminder is open when its current due date is in the week;
    /// - nothing is derived from a series having moved on (no invented completions), undated
    ///   reminders are in no week, and events add nothing (no attended count).
    public static func summary(
        events: [Event],
        reminders: [Reminder],
        weekStarting weekStart: Date,
        today: Date,
        apple: AppleSnapshot = .empty,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> WeeklyReview {
        let start = calendar.startOfDay(for: weekStart)
        let week = range(forWeekStarting: start, calendar: calendar)
        let items = buildAgendaItems(events: events, reminders: reminders, in: week, today: today)

        var completed: [AgendaItem] = []
        var open: [AgendaItem] = []
        for item in items where week.contains(item.occurrence) {
            guard case .reminder = item.kind else { continue }
            if item.isCompleted { completed.append(item) } else { open.append(item) }
        }
        for a in apple.reminders {
            let (reminder, source) = appleReminderValue(a, calendar: calendar)
            let date = a.isCompleted ? (a.completedAt ?? reminder.dueDate) : reminder.dueDate
            guard let date, week.contains(date) else { continue }
            let row = AgendaItem(kind: .reminder(reminder), occurrence: date, displayDate: date,
                                 isOverdue: false, appleSource: source)
            if a.isCompleted { completed.append(row) } else { open.append(row) }
        }
        let byOccurrence: (AgendaItem, AgendaItem) -> Bool = {
            $0.occurrence != $1.occurrence ? $0.occurrence < $1.occurrence : $0.id < $1.id
        }
        return WeeklyReview(
            weekStart: start,
            range: week,
            completed: completed.sorted(by: byOccurrence),
            open: open.sorted(by: byOccurrence)
        )
    }
}
