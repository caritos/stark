// ios/Sources/StarkKit/Planner/TrayPane.swift
import Foundation

/// The planner tray's three panes (`DayPlanModel.trayPast` / `trayToday` / `trayFuture`).
/// `dayWord` is the planned day's word ("TODAY", "TOMORROW"), which names the middle pane.
public enum TrayPane: Int, CaseIterable, Hashable, Sendable {
    case past, today, future

    public func label(dayWord: String) -> String {
        switch self {
        case .past: return "PAST"
        case .today: return dayWord
        case .future: return "FUTURE"
        }
    }

    public func hint(dayWord: String) -> String {
        switch self {
        case .past: return "NEWEST FIRST - OLDER THAN \(dayWord)"
        case .today: return "DUE \(dayWord) - NOT YET PLACED"
        case .future: return "SOONEST FIRST - AFTER \(dayWord)"
        }
    }

    /// e.g. "Past, 87 tasks".
    public func accessibilityLabel(dayWord: String, count: Int) -> String {
        "\(label(dayWord: dayWord).capitalized), \(count) \(count == 1 ? "task" : "tasks")"
    }

    public func items(in model: DayPlanModel) -> [AgendaItem] {
        switch self {
        case .past: return model.trayPast
        case .today: return model.trayToday
        case .future: return model.trayFuture
        }
    }
}
