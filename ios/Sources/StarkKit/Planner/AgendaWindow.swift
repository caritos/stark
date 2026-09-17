// ios/Sources/StarkKit/Planner/AgendaWindow.swift
import Foundation

/// The single source of truth for the agenda's display window (today - 14 days through
/// today + 60 days). `AgendaView` (what the user sees) and `PlannerStore.start` (what gets
/// loaded from disk) must always agree on this range — if they drift, items inside the
/// displayed window but outside the loaded window silently vanish (see issue: agenda items
/// beyond the loaded months disappearing after relaunch).
public enum AgendaWindow {
    public static let daysBefore = 14
    public static let daysAfter = 60

    public static func range(around date: Date) -> ClosedRange<Date> {
        let todayIso = DateMath.isoDate(from: date)
        let start = DateMath.date(from: DateMath.addDays(todayIso, -daysBefore))
        let end = DateMath.date(from: DateMath.addDays(todayIso, daysAfter))
        return start...end
    }
}
