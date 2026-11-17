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
    /// `previous` time on a quarter hour (iOS 26 floors 10:07 to 10:00; another version might show
    /// the nearest) and reports that shown time on ANY change, so changing only the day would
    /// silently move 10:07. The rule does not depend on how UIKit rounds:
    /// - same calendar day as `previous`: the pick always wins (the owner moved the time wheel);
    /// - another day, and the picked wall-clock time within 15 minutes of `previous`'s: the owner
    ///   changed only the day, so `previous`'s exact time is kept on the new day;
    /// - anything else is taken as is.
    /// A restore that would fall below `minimumDate` (the picker's own minimum) is not made: the
    /// pick, which UIKit already clamped to the minimum, is taken instead.
    /// The kept value is the PICK moved by the wall-clock difference (in elapsed seconds), not a
    /// date rebuilt from components, so in a repeated or missing DST hour it stays next to what
    /// the owner picked and never jumps an hour.
    public static func keepingUntouchedTime(picked: Date, previous: Date, minimumDate: Date? = nil,
                                            calendar: Calendar = .current) -> Date {
        guard !calendar.isDate(picked, inSameDayAs: previous) else { return picked }
        let difference = secondsIntoDay(previous, calendar: calendar) - secondsIntoDay(picked, calendar: calendar)
        guard abs(difference) <= TimeInterval(minutes * 60) else { return picked }
        let restored = picked.addingTimeInterval(difference)
        // The Ends picker's minimum is Starts: UIKit clamped the pick to it, and a restore below it
        // would make the end precede the start (stored as no end). Take the clamped pick then.
        if let minimumDate, restored < minimumDate { return picked }
        return restored
    }

    /// "Saved time 10:07" (the locale's short time format) when `date`'s minute is not on a
    /// quarter hour, so the owner sees why the picker shows 10:00 for an item stored at 10:07;
    /// nil when the picker shows the stored time (seconds alone do not count).
    public static func savedTimeCaption(for date: Date, calendar: Calendar = .current,
                                        locale: Locale = .current) -> String? {
        guard calendar.component(.minute, from: date) % minutes != 0 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Saved time \(formatter.string(from: date))"
    }

    /// Wall-clock seconds since midnight (hour, minute, second, fraction), so 01:07 EDT and
    /// 01:07 EST read the same.
    private static func secondsIntoDay(_ date: Date, calendar: Calendar) -> TimeInterval {
        let c = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let hours: Int = c.hour ?? 0
        let minutesIn: Int = c.minute ?? 0
        let seconds: Int = c.second ?? 0
        let whole = TimeInterval(hours * 3600 + minutesIn * 60 + seconds)
        let fraction = TimeInterval(c.nanosecond ?? 0) / 1_000_000_000
        return whole + fraction
    }

    /// True when `date`'s minute is a multiple of 15 and it has no seconds or fraction of one.
    public static func isOnQuarter(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start,
              minuteStart == date else { return false }
        return calendar.component(.minute, from: date) % minutes == 0
    }
}
