// ios/Sources/StarkKit/Items/ReminderAlarmShift.swift
import Foundation

/// Keeps a reminder's alerts with its due date. An alert set in Reminders is either an offset from
/// the due date (moves by itself) or an absolute date (a timed reminder's "at time of due" alert),
/// which EventKit leaves where it was when only the due date changes.
public enum ReminderAlarmShift {
    /// The new absolute dates for the reminder's absolute-date alerts, in order; nil drops that
    /// alert.
    ///
    /// - Timed to timed: every alert moves by the plain difference between the due dates.
    /// - Any change that involves a date-only due (date-only on either side, or the time switched
    ///   on or off): every alert moves by whole calendar days (start of the old due's day to start
    ///   of the new one's) in `calendar`, so it keeps its time of day. A date-only due reads as
    ///   local midnight, so the plain difference would drag a 09:00 alert to 00:00, and a DST
    ///   change would add an hour's drift.
    /// - A cleared due date drops the alerts that were at the old due time and keeps the rest.
    /// - Anything else (unchanged due, no old due) changes nothing.
    public static func shifted(_ alerts: [Date], oldDue: Date?, oldHasTime: Bool, newDue: Date?, newHasTime: Bool,
                               calendar: Calendar) -> [Date?] {
        guard let oldDue, oldDue != newDue || oldHasTime != newHasTime else { return alerts }
        guard let newDue else { return alerts.map { $0 == oldDue ? nil : $0 } }
        guard oldHasTime && newHasTime else {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: oldDue),
                                               to: calendar.startOfDay(for: newDue)).day ?? 0
            return alerts.map { calendar.date(byAdding: .day, value: days, to: $0) ?? $0 }
        }
        let delta = newDue.timeIntervalSince(oldDue)
        return alerts.map { $0.addingTimeInterval(delta) }
    }
}
