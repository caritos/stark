// ios/Sources/StarkKit/Planner/AgendaWindow.swift
import Foundation

/// The single source of truth for the agenda's windows.
///
/// - `range(around:)` is the **display** window (today - 14 days through today + 60 days):
///   what `AgendaView` shows.
/// - `loadRange(around:)` is the **load** window: what `PlannerStore.start` must read from
///   disk. It reaches back `overdueLookbackDays` so overdue reminders older than the display
///   window still exist in memory and can be pinned to today (see `buildAgendaItems`).
///
/// Both windows are **whole days**: the lower bound is the very start of the first day and the
/// upper bound the last second of the last day. (They used to be local noon timestamps, which
/// made `buildAgendaItems`'s `displayRange.contains` silently drop events before noon on the
/// first day and after noon on the last day.)
///
/// The display range must always be a subset of the load range — if it isn't, items inside
/// the displayed window but outside the loaded window silently vanish (see issue: agenda
/// items beyond the loaded months disappearing after relaunch).
///
/// Days are stepped with the calendar, never by adding 86 400 seconds, so a 23- or 25-hour DST
/// day still lands on the right midnight. `calendar` is injectable for tests.
public enum AgendaWindow {
    public static let daysBefore = 14
    public static let daysAfter = 60
    /// How far back an unfinished reminder is still surfaced as overdue.
    public static let overdueLookbackDays = 90

    /// The display window.
    public static func range(around date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> ClosedRange<Date> {
        wholeDays(from: -daysBefore, through: daysAfter, around: date, calendar: calendar)
    }

    /// The window `PlannerStore.start` must load: `overdueLookbackDays` back through
    /// `daysAfter` forward. A superset of `range(around:)`.
    public static func loadRange(around date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> ClosedRange<Date> {
        wholeDays(from: -overdueLookbackDays, through: daysAfter, around: date, calendar: calendar)
    }

    /// Start of the day `first` days from `date`'s day, through the last second of the day
    /// `last` days from it.
    private static func wholeDays(from first: Int, through last: Int, around date: Date, calendar: Calendar) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: date)
        let firstDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: first, to: today)!)
        let dayAfterLast = calendar.startOfDay(for: calendar.date(byAdding: .day, value: last + 1, to: today)!)
        return firstDay...dayAfterLast.addingTimeInterval(-1)
    }
}
