// ios/Sources/StarkKit/Apple/AppleReminderDue.swift
import Foundation

/// Maps an Apple reminder's `dueDateComponents` to the `due` / `dueHasTime` of `AppleReminder`.
///
/// EventKit's components carry Gregorian field values, so they are always resolved with a
/// Gregorian calendar; `components.calendar` (and the phone's own calendar) is ignored. Resolved
/// with a Buddhist or Japanese device calendar, (2026, 11, 15) would be the year 1483 or 4044.
/// The components' own `timeZone` is used when present, otherwise `fallbackTimeZone` (the phone's
/// zone, so a floating due date stays on its wall-clock day). Year, month and day are required;
/// `hasTime` is true when an hour is given. Seconds and smaller fields are ignored.
public func appleReminderDue(_ components: DateComponents,
                             fallbackTimeZone: TimeZone = .current) -> (date: Date?, hasTime: Bool) {
    let hasTime = components.hour != nil
    guard let year = components.year, let month = components.month, let day = components.day else {
        return (nil, hasTime)
    }
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = components.timeZone ?? fallbackTimeZone
    let date = gregorian.date(from: DateComponents(year: year, month: month, day: day,
                                                    hour: components.hour ?? 0,
                                                    minute: components.hour == nil ? 0 : (components.minute ?? 0)))
    return (date, hasTime)
}
