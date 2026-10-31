// ios/Sources/StarkKit/Planner/DayExport.swift
import Foundation

/// One agenda day as plain text for the share sheet (issue #114): an ISO date heading, then a line
/// per item in agenda order. Reminders get a checkbox (an overdue one names its missed date),
/// timed events their 24-hour time.
public enum DayExport {
    public static func text(
        day: Date,
        items: [AgendaItem],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        func iso(_ date: Date) -> String {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return DateMath.isoDate(year: c.year!, month0: c.month! - 1, day: c.day!)
        }
        func line(_ item: AgendaItem) -> String {
            switch item.kind {
            case .event(let event):
                if event.isAllDay { return "- \(event.title)" }
                let c = calendar.dateComponents([.hour, .minute], from: item.occurrence)
                return String(format: "- %02d:%02d %@", c.hour!, c.minute!, event.title)
            case .reminder(let reminder):
                let box = reminder.isCompleted ? "[x]" : "[ ]"
                let late = item.isOverdue ? " (due \(iso(item.occurrence)))" : ""
                return "- \(box) \(reminder.title)\(late)"
            }
        }
        let body = items.isEmpty ? "- (none)" : items.map(line).joined(separator: "\n")
        return "\(iso(day))\n\(body)"
    }
}
