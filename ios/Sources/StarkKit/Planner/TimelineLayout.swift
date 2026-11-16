// ios/Sources/StarkKit/Planner/TimelineLayout.swift
import Foundation

/// A timed event or timed reminder positioned on the hour grid of one day.
public struct TimelineBlock: Equatable, Identifiable, Sendable {
    /// The occurrence's own agenda row id (`<item id>-<start>`), unique within a day.
    public let id: String
    public let title: String
    /// Wall-clock minutes from the day's start, 0...1425 (where the block is drawn).
    public let startMinute: Int
    /// At least `startMinute + 15`, at most 1440.
    public let endMinute: Int
    public let column: Int
    public let columnCount: Int
    public let colorRGB: UInt32?
    public let isReminder: Bool
    public let isCompleted: Bool
    /// The real start and end of the occurrence, for the time text (a block clipped at midnight
    /// or clamped to 23:45 still reads its real times). `end` is nil for a reminder.
    public let start: Date
    public let end: Date?
    /// The real start is before this day / the real end after this day's end (an end exactly at
    /// the next midnight is not "another day": it reads "12:00 AM").
    public let startIsOtherDay: Bool
    public let endIsOtherDay: Bool
}

/// An all-day event, a day-covering multi-day event or a date-only reminder, drawn above the grid.
public struct TimelineChip: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let colorRGB: UInt32?
    public let isHoliday: Bool
    public let isReminder: Bool
    public let isCompleted: Bool
}

public struct DayTimeline: Equatable {
    public let allDay: [TimelineChip]
    public let blocks: [TimelineBlock]
    /// The row each block and chip opens, by its id (a continuation part opens its own occurrence,
    /// which may have no row in the input).
    public let items: [String: AgendaItem]

    public init(allDay: [TimelineChip], blocks: [TimelineBlock], items: [String: AgendaItem] = [:]) {
        self.allDay = allDay
        self.blocks = blocks
        self.items = items
    }
}

/// The agenda rows the Day and Week timelines lay out for the shown `days` (first day's start to
/// the last day's last second): Stark's events over the days, Stark's reminders from
/// min(today, first day) so the agenda's own rules apply (a repeating reminder is listed once: its
/// open row on today, or only its next occurrence, issue #107), Apple items merged from the day
/// before the first (so a daily overnight series' previous occurrence, whose spill row the merge
/// drops by id, is still there), plans applied. Rows outside `days` are left in; `timelineLayout`
/// picks each day's.
public func timelineAgendaItems(events: [Event], reminders: [Reminder], plans: [PlanBlock],
                                apple: AppleSnapshot, days: ClosedRange<Date>, today: Date,
                                calendar: Calendar = Calendar(identifier: .gregorian)) -> [AgendaItem] {
    let first = calendar.startOfDay(for: days.lowerBound)
    let dayBefore = calendar.date(byAdding: .day, value: -1, to: first) ?? first
    let todayStart = calendar.startOfDay(for: today)
    let reminderRange = min(todayStart, first)...max(days.upperBound, min(todayStart, first))
    let local = buildAgendaItems(events: events, reminders: [], in: days, today: today)
        + buildAgendaItems(events: [], reminders: reminders, in: reminderRange, today: today)
    let mergeFrom = min(todayStart, dayBefore)
    let mergeRange = mergeFrom...max(days.upperBound, mergeFrom)
    return agendaWithApple(local: sortAgendaItems(local, calendar: calendar), snapshot: apple, plans: plans,
                           range: mergeRange, today: today, reminders: reminders, calendar: calendar)
}

/// Lays the merged agenda rows out for one `day` as all-day chips and column-packed timed blocks.
/// Pure: no UI types, no `Date()`. Minutes are wall-clock (from the calendar's components), so a
/// DST day still maps 9:00 to minute 540 on a 24-row grid.
///
/// Reminders and all-day events use the rows whose `displayDate` is on `day`. Timed events use the
/// real occurrence intervals behind every event row, whatever its day: a row's own start/end for
/// Apple rows and one-offs, the series expanded over the days that can reach `day` for Stark's
/// own repeating events (their continuation rows carry no offset). Each occurrence is clipped to
/// the day (a block on its first and last day, a chip on a fully covered middle day) and appears
/// once. A timed event that ends exactly at the next midnight does not appear on that day.
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
        let color: UInt32?; let isReminder: Bool; let isCompleted: Bool
        let realStart: Date; let realEnd: Date? }
    var raws: [Raw] = []
    var chips: [TimelineChip] = []
    var opens: [String: AgendaItem] = [:]
    var seen = Set<String>()

    // Clamp to a 15 minute minimum inside the 1440 minute day.
    func clamp(_ start: Int, _ end: Int) -> (Int, Int) {
        let s = min(max(start, 0), 1425)
        return (s, min(max(end, s + 15), 1440))
    }
    func addChip(_ id: String, _ item: AgendaItem, _ title: String, isReminder: Bool, isCompleted: Bool) {
        guard seen.insert(id).inserted else { return }
        opens[id] = item
        chips.append(TimelineChip(id: id, title: title, colorRGB: item.appleSource?.colorRGB,
                                  isHoliday: item.appleSource?.calendarTitle.lowercased().contains("holiday") == true,
                                  isReminder: isReminder, isCompleted: isCompleted))
    }

    for item in items {
        let onDay = calendar.isDate(item.displayDate, inSameDayAs: dayStart)
        let color = item.appleSource?.colorRGB
        switch item.kind {
        case .event(let event):
            if event.isAllDay {
                if onDay { addChip(item.id, item, event.title, isReminder: false, isCompleted: false) }
                continue
            }
            let duration = max(0, (event.end ?? event.start).timeIntervalSince(event.start))
            let starts: [Date]
            if event.recurrence != nil, item.appleSource == nil {
                // A local series' rows are shifted per day: expand the real occurrences that can
                // reach this day instead (a k-day span starts at most k days earlier).
                let span = spanDays(of: event, calendar: calendar)
                let from = calendar.date(byAdding: .day, value: -span, to: dayStart) ?? dayStart
                starts = OccurrenceExpander.expand(event: event, in: from...nextStart.addingTimeInterval(-1))
            } else {
                starts = [event.start]
            }
            for start in starts {
                let end = start.addingTimeInterval(duration)
                // Ends at or before this day's start (incl. exactly midnight), or starts after it.
                if start >= nextStart { continue }
                if end > start ? end <= dayStart : start < dayStart { continue }
                let occurrence = AgendaItem(kind: .event(event), occurrence: start, displayDate: start,
                                            isOverdue: false, appleSource: item.appleSource)
                let id = occurrence.id
                if start < dayStart && end >= nextStart {
                    addChip(id, occurrence, event.title, isReminder: false, isCompleted: false)  // covers the day
                    continue
                }
                guard seen.insert(id).inserted else { continue }
                opens[id] = occurrence
                let s = start < dayStart ? 0 : wall(start)
                var e = end >= nextStart ? 1440 : wall(end)
                // DST fall-back: the wall end can be before the wall start; keep the real length.
                if e < s, end > start { e = min(1440, s + Int(end.timeIntervalSince(start) / 60)) }
                let (cs, ce) = clamp(s, e)
                raws.append(Raw(id: id, title: event.title, start: cs, end: ce, color: color,
                                isReminder: false, isCompleted: false, realStart: start, realEnd: end))
            }
        case .reminder(let reminder):
            guard onDay else { continue }
            let hasTime = calendar.startOfDay(for: item.occurrence) != item.occurrence
            // An overdue row is pinned to today with a missed time: no sensible slot.
            if !hasTime || item.isOverdue || !calendar.isDate(item.occurrence, inSameDayAs: dayStart) {
                addChip(item.id, item, reminder.title, isReminder: true, isCompleted: item.isCompleted)
                continue
            }
            guard seen.insert(item.id).inserted else { continue }
            opens[item.id] = item
            let s = wall(item.occurrence)
            let (cs, ce) = clamp(s, s + 30)
            raws.append(Raw(id: item.id, title: reminder.title, start: cs, end: ce, color: color,
                            isReminder: true, isCompleted: item.isCompleted,
                            realStart: item.occurrence, realEnd: nil))
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
                                        isCompleted: r.isCompleted, start: r.realStart, end: r.realEnd,
                                        startIsOtherDay: r.realStart < dayStart,
                                        endIsOtherDay: r.realEnd.map { $0 > nextStart } ?? false))
        }
        i = j
    }
    return DayTimeline(allDay: chips, blocks: blocks, items: opens)
}
