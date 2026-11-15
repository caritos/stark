// ios/Sources/StarkKit/Items/ReminderAlarmShift.swift
import Foundation

/// Keeps a reminder's alerts with its due date. An alert set in Reminders is either an offset from
/// the due date (moves by itself) or an absolute date (a timed reminder's "at time of due" alert),
/// which EventKit leaves where it was when only the due date changes.
public enum ReminderAlarmShift {
    /// The new absolute dates for the reminder's absolute-date alerts, in order; nil drops that
    /// alert. A moved due date moves every alert by the same amount; a cleared due date drops the
    /// alerts that were at the old due time and keeps the rest; anything else changes nothing.
    public static func shifted(_ alerts: [Date], oldDue: Date?, newDue: Date?) -> [Date?] {
        guard let oldDue, oldDue != newDue else { return alerts }
        guard let newDue else { return alerts.map { $0 == oldDue ? nil : $0 } }
        let delta = newDue.timeIntervalSince(oldDue)
        return alerts.map { $0.addingTimeInterval(delta) }
    }
}
