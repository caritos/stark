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
/// The display range must always be a subset of the load range — if it isn't, items inside
/// the displayed window but outside the loaded window silently vanish (see issue: agenda
/// items beyond the loaded months disappearing after relaunch).
public enum AgendaWindow {
    public static let daysBefore = 14
    public static let daysAfter = 60
    /// How far back an unfinished reminder is still surfaced as overdue.
    public static let overdueLookbackDays = 90

    /// The display window.
    public static func range(around date: Date) -> ClosedRange<Date> {
        let todayIso = DateMath.isoDate(from: date)
        let start = DateMath.date(from: DateMath.addDays(todayIso, -daysBefore))
        let end = DateMath.date(from: DateMath.addDays(todayIso, daysAfter))
        return start...end
    }

    /// The window `PlannerStore.start` must load: `overdueLookbackDays` back through
    /// `daysAfter` forward. A superset of `range(around:)`.
    public static func loadRange(around date: Date) -> ClosedRange<Date> {
        let todayIso = DateMath.isoDate(from: date)
        let start = DateMath.date(from: DateMath.addDays(todayIso, -overdueLookbackDays))
        let end = DateMath.date(from: DateMath.addDays(todayIso, daysAfter))
        return start...end
    }
}
