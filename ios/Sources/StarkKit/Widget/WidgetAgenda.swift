// ios/Sources/StarkKit/Widget/WidgetAgenda.swift
import Foundation

/// One row of the Home Screen widget. Plain values; the widget view only draws them.
public struct WidgetItem: Codable, Equatable, Identifiable, Sendable {
    /// `apple-<id>`, the same id the agenda uses for the item.
    public let id: String
    public let title: String
    public let isReminder: Bool
    /// An all-day event or a date-only reminder (no clock time to show).
    public let isAllDay: Bool
    /// Event start, reminder due date (local midnight for a date-only one).
    public let start: Date
    public let end: Date?
    public let colorHex: String?
    /// An open reminder due before today (red in the widget, as in the app).
    public let isOverdue: Bool
    /// An event of tomorrow (the widget says so, so it is not read as today's).
    public let isTomorrow: Bool

    /// The calendar colour as `0xRRGGBB`, nil when unknown.
    public var colorRGB: UInt32? { AppleColor.rgb(colorHex) }

    public init(id: String, title: String, isReminder: Bool, isAllDay: Bool, start: Date, end: Date?,
                colorHex: String?, isOverdue: Bool, isTomorrow: Bool = false) {
        self.id = id
        self.title = title
        self.isReminder = isReminder
        self.isAllDay = isAllDay
        self.start = start
        self.end = end
        self.colorHex = colorHex
        self.isOverdue = isOverdue
        self.isTomorrow = isTomorrow
    }
}

public enum WidgetAgenda {
    /// What the widget lists, in order: overdue reminders (oldest first, any age, as the agenda
    /// pins them), then today's all-day events and date-only reminders, today's timed events (not
    /// yet ended) and timed reminders by time, then tomorrow's the same way. Events cover now to the
    /// end of tomorrow; reminders are open ones that are overdue or due today. Undated and
    /// completed reminders and excluded calendars are left out. Cut to `limit`.
    public static func items(
        events: [AppleCalendarEvent],
        reminders: [AppleReminder],
        excluded: Set<String>,
        now: Date,
        limit: Int,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [WidgetItem] {
        let todayStart = calendar.startOfDay(for: now)
        guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart),
              let windowEnd = calendar.date(byAdding: .day, value: 2, to: todayStart) else { return [] }

        struct Ranked { let item: WidgetItem; let day: Int; let group: Int }
        var ranked: [Ranked] = []

        for apple in events where !excluded.contains(apple.calendar.id) {
            let start = apple.start
            if apple.isAllDay {
                // `end` is the start of the inclusive last day (`appleEventEnd`).
                let lastDay = calendar.startOfDay(for: apple.end ?? start)
                let firstDay = calendar.startOfDay(for: start)
                guard lastDay >= todayStart, firstDay < windowEnd else { continue }
                let day = firstDay >= tomorrowStart ? 1 : 0
                ranked.append(Ranked(item: eventItem(apple, start: max(firstDay, todayStart), tomorrow: day == 1), day: day, group: 0))
            } else {
                let over = (apple.end.map { $0 > start } ?? false) ? apple.end! : start
                // A zero-length event is over once it has started; a longer one at its end.
                guard start < windowEnd, (over > start ? over > now : start > now) else { continue }
                let isTomorrow = start >= tomorrowStart
                ranked.append(Ranked(item: eventItem(apple, start: start, tomorrow: isTomorrow), day: isTomorrow ? 1 : 0, group: 1))
            }
        }

        for apple in reminders where !excluded.contains(apple.calendar.id) && !apple.isCompleted {
            guard apple.due != nil else { continue }
            let (reminder, source) = appleReminderValue(apple, calendar: calendar)
            guard let due = reminder.dueDate else { continue }
            let overdue = calendar.startOfDay(for: due) < todayStart
            guard overdue || due < tomorrowStart else { continue }
            let dateOnly = !apple.dueHasTime
            let item = WidgetItem(id: reminder.id, title: reminder.title, isReminder: true, isAllDay: dateOnly,
                                  start: due, end: nil, colorHex: source.colorHex, isOverdue: overdue)
            ranked.append(Ranked(item: item, day: overdue ? -1 : 0, group: dateOnly ? 0 : 1))
        }

        ranked.sort { a, b in
            if a.day != b.day { return a.day < b.day }
            if a.group != b.group { return a.group < b.group }
            if a.item.start != b.item.start { return a.item.start < b.item.start }
            if a.item.isReminder != b.item.isReminder { return !a.item.isReminder }
            if a.item.title != b.item.title { return a.item.title < b.item.title }
            return a.item.id < b.item.id
        }
        // Old overdue reminders must not crowd out today's items: at most one overdue row in a short
        // list, two in a longer one, unless nothing else is coming up (then they fill the rows).
        let rows = max(0, limit)
        let overdue = ranked.filter { $0.day < 0 }
        let rest = ranked.filter { $0.day >= 0 }
        let overdueCap = rows >= 5 ? 2 : 1
        let restCount = min(rest.count, rows - min(overdueCap, overdue.count))
        let overdueCount = min(overdue.count, rows - restCount)
        let shown = overdue.prefix(overdueCount) + rest.prefix(restCount)
        return shown.map(\.item)
    }

    private static func eventItem(_ apple: AppleCalendarEvent, start: Date, tomorrow: Bool) -> WidgetItem {
        WidgetItem(id: "apple-\(apple.id)", title: apple.title, isReminder: false, isAllDay: apple.isAllDay,
                   start: start, end: apple.end, colorHex: apple.calendar.colorHex, isOverdue: false,
                   isTomorrow: tomorrow)
    }

    /// When the timeline should next change: the first start or end of a shown timed item after
    /// `now`, else one hour later, and never past the next midnight (all-day items and "today"
    /// roll over then).
    public static func nextRefresh(after now: Date, items: [WidgetItem],
                                   calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        var boundaries: [Date] = []
        for item in items where !item.isAllDay {
            if item.start > now { boundaries.append(item.start) }
            if let end = item.end, end > now { boundaries.append(end) }
        }
        let fallback = now.addingTimeInterval(3600)
        let candidate = boundaries.min() ?? fallback
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? fallback
        return min(candidate, midnight)
    }
}

public extension WidgetAgenda {
    /// The dates of the timeline entries for one fetch: `now`, then each `nextRefresh` of what the
    /// widget would show at the previous date (the largest family, 5 rows), strictly increasing,
    /// at most `maxEntries`, and never at or past the end of tomorrow (the fetch window).
    static func timelineDates(
        events: [AppleCalendarEvent],
        reminders: [AppleReminder],
        excluded: Set<String>,
        now: Date,
        maxEntries: Int = 12,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [Date] {
        guard maxEntries > 0 else { return [] }
        let windowEnd = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(48 * 3600)
        var dates = [now]
        while dates.count < maxEntries, let last = dates.last {
            let shown = items(events: events, reminders: reminders, excluded: excluded, now: last,
                              limit: 5, calendar: calendar)
            let next = nextRefresh(after: last, items: shown, calendar: calendar)
            guard next > last, next < windowEnd else { break }
            dates.append(next)
        }
        return dates
    }
}

/// The calendar selection as the widget reads it from the App Group suite. The app writes it
/// every time its selection changes and keeps reading its own `UserDefaults.standard`; a missing
/// or unreadable value means "show everything".
public enum SelectionMirror {
    public static let suiteName = "group.com.caritos.todo-txt"
    public static let key = "widget.excludedCalendarIDs.v1"

    public static func encode(_ ids: Set<String>) -> Data {
        (try? JSONEncoder().encode(ids.sorted())) ?? Data("[]".utf8)
    }

    public static func decode(_ data: Data?) -> Set<String> {
        guard let data, let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    public static func write(_ ids: Set<String>, to defaults: UserDefaults) {
        defaults.set(encode(ids), forKey: key)
    }

    public static func excludedIDs(from defaults: UserDefaults) -> Set<String> {
        decode(defaults.data(forKey: key))
    }
}
