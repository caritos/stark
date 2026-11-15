// ios/Sources/StarkKit/Planner/TrayPane.swift
import Foundation

/// The planner tray's panes (`DayPlanModel.trayPast` / `trayToday` / `trayFuture`, plus
/// `trayNoDate` for undated Apple reminders). `dayWord` is the planned day's word ("TODAY",
/// "TOMORROW"), which names the middle pane.
public enum TrayPane: Int, CaseIterable, Hashable, Sendable {
    case past, today, future
    /// Undated Apple reminders (spec Decision 3). Shown only when it has items: see
    /// `panes(for:)`.
    case noDate

    /// The three dated panes, always shown. `.noDate` is left out on purpose: it appears only
    /// for a model with undated reminders (`panes(for:)`).
    public static var allCases: [TrayPane] { [.past, .today, .future] }

    /// The panes the tray shows for `model`: the dated three, plus `.noDate` when it has items.
    public static func panes(for model: DayPlanModel) -> [TrayPane] {
        model.trayNoDate.isEmpty ? allCases : allCases + [.noDate]
    }

    /// The pane to keep selected when the tray shows `panes`: `selected` while it is still shown,
    /// else the planned day's own pane (`.noDate` empties once its last reminder is planned).
    public static func shown(_ selected: TrayPane, among panes: [TrayPane]) -> TrayPane {
        panes.contains(selected) ? selected : .today
    }

    public func label(dayWord: String) -> String {
        switch self {
        case .past: return "PAST"
        case .today: return dayWord
        case .future: return "FUTURE"
        case .noDate: return "NO DATE"
        }
    }

    public func hint(dayWord: String) -> String {
        switch self {
        case .past: return "NEWEST FIRST - OLDER THAN \(dayWord)"
        case .today: return "DUE \(dayWord) - NOT YET PLACED"
        case .future: return "SOONEST FIRST - AFTER \(dayWord)"
        case .noDate: return "A TO Z - NO DUE DATE"
        }
    }

    /// e.g. "Past, 87 tasks", "No date, 2 tasks" (sentence case).
    public func accessibilityLabel(dayWord: String, count: Int) -> String {
        let lower = label(dayWord: dayWord).lowercased()
        return "\(lower.prefix(1).uppercased() + lower.dropFirst()), \(count) \(count == 1 ? "task" : "tasks")"
    }

    public func items(in model: DayPlanModel) -> [AgendaItem] {
        switch self {
        case .past: return model.trayPast
        case .today: return model.trayToday
        case .future: return model.trayFuture
        case .noDate: return model.trayNoDate
        }
    }
}
