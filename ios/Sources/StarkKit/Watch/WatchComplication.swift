import Foundation

/// What one watch complication entry shows, derived from the stored snapshot. Plain values; the
/// widget views only draw them. Never blank: with no rows, `message` says why.
public struct WatchComplicationContent: Equatable, Sendable {
    /// Set when there is nothing to list ("Open Stark on iPhone", "Nothing coming up", ...).
    public let message: String?
    /// The next rows as Lock Screen lines (at most 3), for the rectangular family.
    public let lines: [WidgetLockLine]
    /// The line the inline family shows.
    public let inline: WidgetLockLine?
    /// Items left today (tomorrow's excluded), for the circular and corner families.
    public let count: Int
    /// The rows behind `lines`, for accessibility labels.
    public let items: [WidgetItem]

    public init(message: String?, lines: [WidgetLockLine], inline: WidgetLockLine?, count: Int,
                items: [WidgetItem]) {
        self.message = message
        self.lines = lines
        self.inline = inline
        self.count = count
        self.items = items
    }
}

public enum WatchComplication {
    /// A snapshot older than this is not trusted (same rule as `WatchAgendaModel.stale(after:)`).
    public static let staleAfter: TimeInterval = 3 * 3600
    public static let openMessage = "Open Stark on iPhone"
    public static let maxEntries = 12

    public static func countText(_ count: Int) -> String { WidgetRowText.countText(count) }

    /// The entry for `now`: rows still current at `now` (ended events dropped, tomorrow's turned
    /// into today's after midnight), or a message.
    public static func content(snapshot: WatchSnapshot?, now: Date,
                               calendar: Calendar = Calendar(identifier: .gregorian),
                               locale: Locale = .autoupdatingCurrent) -> WatchComplicationContent {
        func message(_ text: String) -> WatchComplicationContent {
            WatchComplicationContent(message: text, lines: [], inline: nil, count: 0, items: [])
        }
        guard let snapshot, now.timeIntervalSince(snapshot.generatedAt) <= staleAfter else {
            return message(openMessage)
        }
        switch snapshot.state {
        case .accessNeeded(let text): return message(text.isEmpty ? "Allow Calendar access on iPhone" : text)
        case .noSources: return message("No calendars are syncing")
        case .empty: return message("Nothing coming up")
        case .failed: return message("Couldn't read calendar. Open Stark on iPhone")
        case .items: break
        }
        let live = snapshot.rows.compactMap { current($0.item, at: now, calendar: calendar) }
        guard !live.isEmpty else { return message("Nothing coming up") }
        let lines = live.prefix(3).map { WidgetRowText.lockLine($0, calendar: calendar, locale: locale) }
        let inline = WidgetAgenda.inlineItem(from: live).map {
            WidgetRowText.lockLine($0, calendar: calendar, locale: locale)
        }
        return WatchComplicationContent(message: nil, lines: Array(lines), inline: inline,
                                        count: live.filter { !$0.isTomorrow }.count,
                                        items: Array(live.prefix(3)))
    }

    /// The row as it reads at `date`, or nil when it is over.
    private static func current(_ item: WidgetItem, at date: Date, calendar: Calendar) -> WidgetItem? {
        let today = calendar.startOfDay(for: date)
        let day = calendar.startOfDay(for: item.start)
        let isOverdue = item.isReminder ? (item.isOverdue || day < today) : false
        let isTomorrow = !isOverdue && day > today
        if item.isReminder {
            // Overdue reminders stay; a reminder is listed until the phone says it is done.
        } else if item.isAllDay {
            guard calendar.startOfDay(for: item.end ?? item.start) >= today else { return nil }
        } else {
            let over = (item.end.map { $0 > item.start } ?? false) ? item.end! : item.start
            guard over > item.start ? over > date : item.start > date else { return nil }
        }
        if item.isAllDay && !item.isReminder && day < today {
            return WidgetItem(id: item.id, title: item.title, isReminder: false, isAllDay: true, start: today,
                              end: item.end, colorHex: item.colorHex, isOverdue: false, isTomorrow: false)
        }
        if isOverdue == item.isOverdue && isTomorrow == item.isTomorrow { return item }
        return WidgetItem(id: item.id, title: item.title, isReminder: item.isReminder, isAllDay: item.isAllDay,
                          start: item.start, end: item.end, colorHex: item.colorHex, isOverdue: isOverdue,
                          isTomorrow: isTomorrow)
    }

    /// Entry dates: `now`, then the next start or end of what shows, then the moment the snapshot
    /// turns stale (so the "Open Stark" message takes over), never more than `maxEntries`.
    public static func entryDates(snapshot: WatchSnapshot?, now: Date,
                                  calendar: Calendar = Calendar(identifier: .gregorian)) -> [Date] {
        guard let snapshot else { return [now] }
        let cutoff = snapshot.generatedAt.addingTimeInterval(staleAfter)
        guard cutoff > now, snapshot.state == .items else { return [now] }
        var dates = [now]
        while dates.count < maxEntries, let last = dates.last {
            let shown = snapshot.rows.compactMap { current($0.item, at: last, calendar: calendar) }
            let next = min(WidgetAgenda.nextRefresh(after: last, items: shown, calendar: calendar), cutoff)
            guard next > last else { break }
            dates.append(next)
            if next >= cutoff { break }
        }
        return dates
    }

    /// When the timeline asks for a new one: the last entry or an hour from `now`, whichever is first.
    public static func reloadDate(after now: Date, entryDates: [Date]) -> Date {
        let hour = now.addingTimeInterval(3600)
        guard let last = entryDates.last, entryDates.count > 1 else { return hour }
        return min(last, hour)
    }
}
