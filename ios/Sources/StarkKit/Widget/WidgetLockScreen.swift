// ios/Sources/StarkKit/Widget/WidgetLockScreen.swift
import Foundation

public extension WidgetAgenda {
    /// How many items are left today for the circular Lock Screen widget: the rows `items` would
    /// list with no row limit (so every overdue reminder counts, not only the capped rows), minus
    /// tomorrow's.
    static func remainingToday(events: [AppleCalendarEvent], reminders: [AppleReminder], excluded: Set<String>,
                               now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        items(events: events, reminders: reminders, excluded: excluded, now: now, limit: .max, calendar: calendar)
            .filter { !$0.isTomorrow }
            .count
    }
}

/// One Lock Screen line: an optional time prefix and the title, kept apart so the view can mark
/// only the title privacy-sensitive.
public struct WidgetLockLine: Equatable, Sendable {
    public let time: String?
    public let title: String
    public var text: String { [time, title].compactMap { $0 }.joined(separator: " ") }
}

public extension WidgetRowText {
    /// The circular widget's number, "9+" above nine.
    static func countText(_ count: Int) -> String { count > 9 ? "9+" : String(max(0, count)) }

    static func countAccessibilityLabel(_ count: Int) -> String {
        switch count {
        case ..<1: return "Nothing left today"
        case 1: return "1 item left today"
        default: return "\(count) items left today"
        }
    }

    /// "9:00 AM Standup"; an all-day item and an overdue reminder are the title alone (the lock
    /// screen is monochrome, so no red); tomorrow's say "Tmrw 9:00 AM" / "Tomorrow".
    static func lockLine(_ item: WidgetItem, calendar: Calendar = .current,
                         locale: Locale = .autoupdatingCurrent) -> WidgetLockLine {
        let title = item.title.isEmpty ? "Untitled" : item.title
        let time: String?
        if item.isOverdue {
            time = nil
        } else if item.isAllDay {
            time = item.isTomorrow ? "Tomorrow" : nil
        } else {
            time = WidgetRowText.time(item, calendar: calendar, locale: locale)
        }
        return WidgetLockLine(time: time, title: title)
    }
}
