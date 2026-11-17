// ios/Sources/StarkKit/Models/QuarterHour.swift
import Foundation

/// The add/edit time pickers offer only :00, :15, :30 and :45. These are the pure rules behind
/// them: a new item's default start (the next quarter hour) and whether a time is already on one.
/// The steps are taken in elapsed time from the start of the minute, so on a DST change they land
/// on the wall clock's next quarter hour (01:50 EST -> 03:00 EDT; 01:50 EDT -> 01:00 EST).
public enum QuarterHour {
    /// The step of the pickers' minute wheel.
    public static let minutes = 15

    /// `date` itself when it is exactly on a quarter hour (no seconds), else the first quarter
    /// hour after it, with seconds dropped.
    public static func nextAfter(_ date: Date, calendar: Calendar = .current) -> Date {
        if isOnQuarter(date, calendar: calendar) { return date }
        let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        let minute = calendar.component(.minute, from: minuteStart)
        let step = minutes - minute % minutes
        return minuteStart.addingTimeInterval(TimeInterval(step * 60))
    }

    /// The quarter hour at or before `date`, seconds dropped: what a `minuteInterval = 15`
    /// UIDatePicker shows for an odd time (seen on iOS 26: 10:07 and 10:13 both show 10:00).
    public static func floored(_ date: Date, calendar: Calendar = .current) -> Date {
        let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        let minute = calendar.component(.minute, from: minuteStart)
        return minuteStart.addingTimeInterval(-TimeInterval((minute % minutes) * 60))
    }

    /// The value to store after the owner changed a quarter-hour picker. The picker shows an odd
    /// `previous` time floored (10:07 as 10:00) and reports that shown time on ANY change, so a
    /// change of only the day would silently move 10:07 to 10:00. When the picked wall-clock time
    /// is exactly the shown one, the owner did not touch the time: the new day keeps `previous`'s
    /// exact time. Any other pick is taken as is.
    public static func keepingUntouchedTime(picked: Date, previous: Date,
                                            calendar: Calendar = .current) -> Date {
        guard !isOnQuarter(previous, calendar: calendar) else { return picked }
        let clock: Set<Calendar.Component> = [.hour, .minute]
        let shown = calendar.dateComponents(clock, from: floored(previous, calendar: calendar))
        guard calendar.dateComponents(clock, from: picked) == shown else { return picked }
        var kept = calendar.dateComponents([.era, .year, .month, .day], from: picked)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: previous)
        kept.hour = time.hour
        kept.minute = time.minute
        kept.second = time.second
        kept.nanosecond = time.nanosecond
        return calendar.date(from: kept) ?? picked
    }

    /// True when `date`'s minute is a multiple of 15 and it has no seconds or fraction of one.
    public static func isOnQuarter(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start,
              minuteStart == date else { return false }
        return calendar.component(.minute, from: date) % minutes == 0
    }
}
