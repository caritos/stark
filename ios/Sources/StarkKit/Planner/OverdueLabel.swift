import Foundation

public enum OverdueLabel {
    public static func text(daysOverdue: Int, lookbackDays: Int = AgendaWindow.overdueLookbackDays) -> String {
        if daysOverdue >= lookbackDays { return "\(lookbackDays)+ days overdue" }
        return daysOverdue == 1 ? "1 day overdue" : "\(daysOverdue) days overdue"
    }
}

extension AgendaItem {
    /// Whole calendar days from the missed occurrence to `today`, or nil when not overdue.
    public func daysOverdue(today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int? {
        guard isOverdue else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: occurrence), to: calendar.startOfDay(for: today)).day ?? 1
        return max(1, days)
    }
}
