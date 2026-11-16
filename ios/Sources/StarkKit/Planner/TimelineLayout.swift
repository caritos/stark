// ios/Sources/StarkKit/Planner/TimelineLayout.swift
import Foundation

/// A timed event or timed reminder positioned on the hour grid of one day.
public struct TimelineBlock: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    /// Wall-clock minutes from the day's start, 0...1425.
    public let startMinute: Int
    /// At least `startMinute + 15`, at most 1440.
    public let endMinute: Int
    public let column: Int
    public let columnCount: Int
    public let colorRGB: UInt32?
    public let isReminder: Bool
    public let isCompleted: Bool
}

/// An all-day event, a day-covering multi-day event or a date-only reminder, drawn above the grid.
public struct TimelineChip: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let colorRGB: UInt32?
    public let isHoliday: Bool
}

public struct DayTimeline: Equatable, Sendable {
    public let allDay: [TimelineChip]
    public let blocks: [TimelineBlock]
}

/// Lays the merged agenda rows of one `day` out as all-day chips and column-packed timed blocks.
/// Pure: no UI types, no `Date()`. Minutes are wall-clock (from the calendar's components), so a
/// DST day still maps 9:00 to minute 540 on a 24-row grid. Rows whose `displayDate` is another day
/// are ignored. A timed event that ends exactly at the next midnight does not appear on that day.
public func timelineLayout(items: [AgendaItem], day: Date,
                           calendar: Calendar = Calendar(identifier: .gregorian)) -> DayTimeline {
    let dayStart = calendar.startOfDay(for: day)
    guard let nextStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
        return DayTimeline(allDay: [], blocks: [])
    }
    func wall(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    struct Raw { let id: String; let title: String; var start: Int; var end: Int
        let color: UInt32?; let isReminder: Bool; let isCompleted: Bool }
    var raws: [Raw] = []
    var chips: [TimelineChip] = []

    // Clamp to a 15 minute minimum inside the 1440 minute day.
    func clamp(_ start: Int, _ end: Int) -> (Int, Int) {
        let s = min(max(start, 0), 1425)
        return (s, min(max(end, s + 15), 1440))
    }

    for item in items where calendar.isDate(item.displayDate, inSameDayAs: dayStart) {
        let color = item.appleSource?.colorRGB
        switch item.kind {
        case .event(let event):
            if event.isAllDay {
                chips.append(chip(item, event.title, color))
                continue
            }
            // The row's own start and end. Apple rows and one-offs carry the real instants; a
            // local series' rows are shifted per day, so rebuild its wall-clock start on this day.
            var start = event.start
            var end = event.end ?? event.start
            if event.recurrence != nil, item.appleSource == nil {
                let c = calendar.dateComponents([.hour, .minute], from: event.start)
                start = calendar.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: dayStart) ?? dayStart
                end = start.addingTimeInterval(max(0, end.timeIntervalSince(event.start)))
            }
            if end < start { end = start }
            // Ends at or before this day's start (incl. exactly midnight): not on this day.
            if end <= dayStart && end > start || end < dayStart { continue }
            if start >= nextStart { continue }
            if start < dayStart && end >= nextStart {
                chips.append(chip(item, event.title, color))  // covers the whole day
                continue
            }
            let s = start < dayStart ? 0 : wall(start)
            let e = end >= nextStart ? 1440 : wall(end)
            let (cs, ce) = clamp(s, e)
            raws.append(Raw(id: item.id, title: event.title, start: cs, end: ce, color: color,
                            isReminder: false, isCompleted: false))
        case .reminder(let reminder):
            let hasTime = calendar.startOfDay(for: item.occurrence) != item.occurrence
            // An overdue row is pinned to today with a missed time: no sensible slot.
            if !hasTime || item.isOverdue || !calendar.isDate(item.occurrence, inSameDayAs: dayStart) {
                chips.append(chip(item, reminder.title, color))
                continue
            }
            let s = wall(item.occurrence)
            let (cs, ce) = clamp(s, s + 30)
            raws.append(Raw(id: item.id, title: reminder.title, start: cs, end: ce, color: color,
                            isReminder: true, isCompleted: item.isCompleted))
        }
    }

    // Overlap clusters: start ascending, longer first; touching blocks do not overlap.
    raws.sort {
        if $0.start != $1.start { return $0.start < $1.start }
        if $0.end != $1.end { return $0.end > $1.end }
        return $0.id < $1.id
    }
    var blocks: [TimelineBlock] = []
    var i = 0
    while i < raws.count {
        var clusterEnd = raws[i].end
        var j = i
        var colEnds: [Int] = []
        var assigned: [Int] = []
        while j < raws.count, raws[j].start < clusterEnd || j == i {
            let r = raws[j]
            if let free = colEnds.firstIndex(where: { $0 <= r.start }) {
                colEnds[free] = r.end; assigned.append(free)
            } else {
                colEnds.append(r.end); assigned.append(colEnds.count - 1)
            }
            clusterEnd = max(clusterEnd, r.end)
            j += 1
        }
        for k in i..<j {
            let r = raws[k]
            blocks.append(TimelineBlock(id: r.id, title: r.title, startMinute: r.start, endMinute: r.end,
                                        column: assigned[k - i], columnCount: colEnds.count,
                                        colorRGB: r.color, isReminder: r.isReminder,
                                        isCompleted: r.isCompleted))
        }
        i = j
    }
    return DayTimeline(allDay: chips, blocks: blocks)
}

private func chip(_ item: AgendaItem, _ title: String, _ color: UInt32?) -> TimelineChip {
    TimelineChip(id: item.id, title: title, colorRGB: color,
                 isHoliday: item.appleSource?.calendarTitle.lowercased().contains("holiday") == true)
}
