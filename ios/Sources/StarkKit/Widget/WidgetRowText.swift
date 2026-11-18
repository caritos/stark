// ios/Sources/StarkKit/Widget/WidgetRowText.swift
import Foundation

/// The text of one widget row, kept out of the view so it is tested.
public enum WidgetRowText {
    /// The short time line: "All day" for an all-day event, nothing for a date-only reminder due
    /// today, the missed date ("Jun 1") for an overdue reminder, else the clock time.
    public static func time(_ item: WidgetItem, calendar: Calendar = .current,
                            locale: Locale = .autoupdatingCurrent) -> String? {
        if item.isOverdue { return dateText(item.start, calendar: calendar, locale: locale) }
        if item.isAllDay { return item.isReminder ? nil : "All day" }
        return clock(item.start, calendar: calendar, locale: locale)
    }

    /// "Event, Team sync, 2:30 PM" / "Reminder, Pay rent, overdue since Jun 1" / "Event, Trip, all day".
    public static func accessibilityLabel(_ item: WidgetItem, calendar: Calendar = .current,
                                          locale: Locale = .autoupdatingCurrent) -> String {
        let kind = item.isReminder ? "Reminder" : "Event"
        var parts = [kind, item.title]
        if item.isOverdue {
            parts.append("overdue since \(dateText(item.start, calendar: calendar, locale: locale))")
        } else if item.isAllDay {
            parts.append(item.isReminder ? "due today" : "all day")
        } else {
            parts.append(clock(item.start, calendar: calendar, locale: locale))
        }
        return parts.joined(separator: ", ")
    }

    private static func clock(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }

    private static func dateText(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }
}
