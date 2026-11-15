// ios/Sources/StarkKit/Apple/AppleMerge.swift
import Foundation

/// Adds the read-only Apple Calendar / Reminders rows to Stark's agenda items and re-sorts.
///
/// Apple items become synthetic, never-persisted `Event` / `Reminder` values with id
/// `apple-<id>` and no recurrence (EventKit already expands a series into occurrences), so they
/// can never collide with Stark's UUIDs. `range` is the display range; reminders are also
/// considered back `AgendaWindow.overdueLookbackDays` from `today`.
///
/// - Events: one row per day spanned (same `spanDays` rule as `buildAgendaItems`; an all-day end is its last day, inclusive, as in Stark). A timed event
///   ending exactly at a midnight does not spill onto that day (its end is exclusive). Row ids are
///   unique: a spill-over row that would repeat a later occurrence's own row (daily overnight
///   series) is dropped.
/// - Open reminders due before today (inside the lookback) are overdue, pinned to start-of-today
///   with the due date kept in `occurrence`; older ones are dropped.
/// - Completed reminders show on their due day and are never overdue.
/// - Reminders without a due date are dropped.
/// - A reminder with `dueHasTime == false` is stored at local midnight, which is Stark's marker
///   for a date-only due date (`FormFields.isAllDay`).
public func mergeAppleItems(
    _ items: [AgendaItem],
    snapshot: AppleSnapshot,
    in range: ClosedRange<Date>,
    today: Date,
    calendar: Calendar = Calendar(identifier: .gregorian)
) -> [AgendaItem] {
    let todayStart = calendar.startOfDay(for: today)
    let lookbackStart = calendar.date(byAdding: .day, value: -AgendaWindow.overdueLookbackDays, to: todayStart) ?? todayStart
    var merged = items

    // Own-day rows first, spill-over rows (k > 0) after, keeping only the first row per id. A
    // spill-over row's occurrence is start + k days, which in a daily overnight series (22:00 to
    // 02:00) is the next occurrence's own start, so both rows would share an id; the
    // occurrence's own row wins.
    var ownRows: [AgendaItem] = []
    var spillRows: [AgendaItem] = []
    for apple in snapshot.events {
        let source = AppleSource(calendarID: apple.calendar.id, calendarTitle: apple.calendar.title,
                                 colorHex: apple.calendar.colorHex, isReminder: false)
        let event = Event(id: "apple-\(apple.id)", title: apple.title, notes: apple.notes, start: apple.start,
                          end: apple.end, isAllDay: apple.isAllDay, location: apple.location, url: apple.url)
        // An end exactly at midnight is exclusive: measure the span to the last instant before it.
        var spanEvent = event
        if !apple.isAllDay, let end = apple.end, end > apple.start, calendar.startOfDay(for: end) == end {
            spanEvent.end = end.addingTimeInterval(-1)
        }
        let span = spanDays(of: spanEvent, calendar: calendar)
        for k in 0...span {
            let day = k == 0 ? apple.start : (calendar.date(byAdding: .day, value: k, to: apple.start) ?? apple.start)
            guard range.contains(day) else { continue }
            let row = AgendaItem(kind: .event(event), occurrence: day, displayDate: day, isOverdue: false,
                                 appleSource: source)
            if k == 0 { ownRows.append(row) } else { spillRows.append(row) }
        }
    }
    var emittedIDs = Set<String>()
    for row in ownRows + spillRows where emittedIDs.insert(row.id).inserted {
        merged.append(row)
    }

    for apple in snapshot.reminders {
        guard let rawDue = apple.due else { continue }
        let due = apple.dueHasTime ? rawDue : calendar.startOfDay(for: rawDue)
        let source = AppleSource(calendarID: apple.calendar.id, calendarTitle: apple.calendar.title,
                                 colorHex: apple.calendar.colorHex, isReminder: true, url: apple.url)
        let reminder = Reminder(id: "apple-\(apple.id)", title: apple.title, notes: apple.notes, dueDate: due,
                                isCompleted: apple.isCompleted, completedDate: apple.isCompleted ? due : nil,
                                priority: apple.priority, completedAt: apple.completedAt)
        if apple.isCompleted {
            if range.contains(due) {
                merged.append(AgendaItem(kind: .reminder(reminder), occurrence: due, displayDate: due,
                                         isOverdue: false, appleSource: source))
            }
        } else if calendar.startOfDay(for: due) < todayStart {
            guard due >= lookbackStart else { continue }
            merged.append(AgendaItem(kind: .reminder(reminder), occurrence: due, displayDate: todayStart,
                                     isOverdue: true, appleSource: source))
        } else if range.contains(due) {
            merged.append(AgendaItem(kind: .reminder(reminder), occurrence: due, displayDate: due,
                                     isOverdue: false, appleSource: source))
        }
    }

    return sortAgendaItems(merged, calendar: calendar)
}

/// Maps EventKit's end date to the `AppleCalendarEvent.end` that `mergeAppleItems` expects.
/// Timed events pass through (a midnight end is exclusive in the merge). For an all-day event
/// the result is the start of its INCLUSIVE last day: EventKit usually reports 23:59:59 on the
/// last day, but an end at exactly the next midnight is stepped back a day so no extra row
/// appears. Never earlier than the start's day.
public func appleEventEnd(start: Date, end: Date?, isAllDay: Bool,
                          calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
    guard let end else { return nil }
    guard isAllDay else { return end }
    let startDay = calendar.startOfDay(for: start)
    var lastDay = calendar.startOfDay(for: end)
    if end == lastDay, lastDay > startDay {
        lastDay = calendar.date(byAdding: .day, value: -1, to: lastDay) ?? lastDay
    }
    return max(lastDay, startDay)
}
