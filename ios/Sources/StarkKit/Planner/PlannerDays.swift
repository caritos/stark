// ios/Sources/StarkKit/Planner/PlannerDays.swift
import Foundation

/// Day helpers for the planner's day stepping.
public enum PlannerDays {
    /// A day is editable from today on; earlier days are read-only history.
    public static func isEditable(_ day: Date, today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        calendar.startOfDay(for: day) >= calendar.startOfDay(for: today)
    }

    /// Start of the day `days` away from `day` (stepped with the calendar, never 86 400 s).
    public static func step(_ day: Date, by days: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: days, to: start) ?? start)
    }

    /// What must be loaded for `day`: its Sunday-Saturday week widened by the overdue lookback,
    /// and always `AgendaWindow.loadRange(around: day)` itself.
    public static func loadRange(for day: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> ClosedRange<Date> {
        let start = calendar.startOfDay(for: day)
        let weekday = calendar.component(.weekday, from: start)
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: start) ?? start
        let saturday = calendar.date(byAdding: .day, value: 6, to: sunday) ?? start
        let own = AgendaWindow.loadRange(around: start, calendar: calendar)
        let lower = min(AgendaWindow.loadRange(around: sunday, calendar: calendar).lowerBound, own.lowerBound)
        let upper = max(AgendaWindow.loadRange(around: saturday, calendar: calendar).upperBound, own.upperBound)
        return lower...upper
    }
}
