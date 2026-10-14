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
    /// Completed reminders due in the week, by occurrence.
    public let completed: [AgendaItem]
    /// Incomplete reminders whose (possibly missed) occurrence is in the week, by occurrence.
    public let open: [AgendaItem]
    /// Event occurrences in the week marked attended.
    public let attendedEventCount: Int

    /// e.g. "14 done · 3 open".
    public var countsLabel: String { "\(completed.count) done · \(open.count) open" }

    /// e.g. "Events attended: 2".
    public var attendedLabel: String { "Events attended: \(attendedEventCount)" }

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

    public static func summary(
        events: [Event],
        reminders: [Reminder],
        weekStarting weekStart: Date,
        today: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> WeeklyReview {
        let start = calendar.startOfDay(for: weekStart)
        let week = range(forWeekStarting: start, calendar: calendar)
        let items = buildAgendaItems(events: events, reminders: reminders, in: week, today: today)

        var completed: [AgendaItem] = []
        var open: [AgendaItem] = []
        var attended = 0
        for item in items where week.contains(item.occurrence) {
            switch item.kind {
            case .event:
                if item.outcome == .attended { attended += 1 }
            case .reminder:
                if item.isCompleted { completed.append(item) } else { open.append(item) }
            }
        }
        let byOccurrence: (AgendaItem, AgendaItem) -> Bool = {
            $0.occurrence != $1.occurrence ? $0.occurrence < $1.occurrence : $0.id < $1.id
        }
        return WeeklyReview(
            weekStart: start,
            range: week,
            completed: completed.sorted(by: byOccurrence),
            open: open.sorted(by: byOccurrence),
            attendedEventCount: attended
        )
    }
}
