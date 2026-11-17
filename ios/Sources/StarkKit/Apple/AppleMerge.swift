// ios/Sources/StarkKit/Apple/AppleMerge.swift
import Foundation

/// Adds the Apple Calendar / Reminders rows to Stark's agenda items and re-sorts. The rows are
/// edited through `ItemRouter` (writable calendars); only non-writable calendars and invitee-only
/// events stay read-only.
///
/// Apple items become synthetic, never-persisted `Event` / `Reminder` values with id
/// `apple-<id>` and no recurrence (EventKit already expands a series into occurrences), so they
/// can never collide with Stark's UUIDs. `range` is the display range; open reminders
/// of any age are considered (EventKit holds one current occurrence, so there is no run to bound).
///
/// - Events: one row per day spanned (same `spanDays` rule as `buildAgendaItems`; an all-day end is its last day, inclusive, as in Stark). A timed event
///   ending exactly at a midnight does not spill onto that day (its end is exclusive). Row ids are
///   unique: a spill-over row that would repeat a later occurrence's own row (daily overnight
///   series) is dropped.
/// - Open reminders due before today are overdue at ANY age, pinned to start-of-today with the
///   due date kept in `occurrence` (the 90-day lookback applies to Stark's own items only).
/// - Completed reminders show on their due day and are never overdue.
/// - Reminders without a due date are dropped (they never show in the agenda; see
///   `undatedAppleReminders`).
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
    var merged = items

    // Own-day rows first, spill-over rows (k > 0) after, keeping only the first row per id. A
    // spill-over row's occurrence is start + k days, which in a daily overnight series (22:00 to
    // 02:00) is the next occurrence's own start, so both rows would share an id; the
    // occurrence's own row wins.
    var ownRows: [AgendaItem] = []
    var spillRows: [AgendaItem] = []
    for apple in snapshot.events {
        let source = AppleSource(calendarID: apple.calendar.id, calendarTitle: apple.calendar.title,
                                 colorHex: apple.calendar.colorHex, isReminder: false,
                                 isWritable: apple.calendar.isWritable)
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
        guard apple.due != nil else { continue }
        let (reminder, source) = appleReminderValue(apple, calendar: calendar)
        guard let due = reminder.dueDate else { continue }
        if apple.isCompleted {
            if range.contains(due) {
                merged.append(AgendaItem(kind: .reminder(reminder), occurrence: due, displayDate: due,
                                         isOverdue: false, appleSource: source))
            }
        } else if calendar.startOfDay(for: due) < todayStart {
            merged.append(AgendaItem(kind: .reminder(reminder), occurrence: due, displayDate: todayStart,
                                     isOverdue: true, appleSource: source))
        } else if range.contains(due) {
            merged.append(AgendaItem(kind: .reminder(reminder), occurrence: due, displayDate: due,
                                     isOverdue: false, appleSource: source))
        }
    }

    return sortAgendaItems(merged, calendar: calendar)
}

/// The synthetic `Reminder` (id `apple-<id>`, no recurrence) and its `AppleSource` for one Apple
/// reminder, exactly as `mergeAppleItems` builds them: a date-only due date is local midnight, a
/// completed reminder's `completedDate` is its due date. Shared by every engine that reads Apple
/// reminders so they all agree on ids and dates.
func appleReminderValue(_ apple: AppleReminder, calendar: Calendar) -> (Reminder, AppleSource) {
    let due = apple.due.map { apple.dueHasTime ? $0 : calendar.startOfDay(for: $0) }
    let source = AppleSource(calendarID: apple.calendar.id, calendarTitle: apple.calendar.title,
                             colorHex: apple.calendar.colorHex, isReminder: true, url: apple.url,
                             isWritable: apple.calendar.isWritable, isRecurringSeries: apple.isRecurring)
    let reminder = Reminder(id: ItemOrigin.applePrefix + apple.id, title: apple.title, notes: apple.notes,
                            dueDate: due, isCompleted: apple.isCompleted,
                            completedDate: apple.isCompleted ? due : nil,
                            priority: apple.priority, completedAt: apple.completedAt)
    return (reminder, source)
}

/// The open Apple reminders with no due date, as rows for Search and the planner's "No date" pane
/// (spec Decision 3). Never part of the agenda (`mergeAppleItems` drops them). `occurrence` and
/// `displayDate` are `.distantFuture`, a stable sentinel that sorts last and keeps each row's `id`
/// fixed; completed undated reminders are left out. Sorted by title, then id.
public func undatedAppleReminders(
    _ snapshot: AppleSnapshot,
    calendar: Calendar = Calendar(identifier: .gregorian)
) -> [AgendaItem] {
    snapshot.reminders
        .filter { $0.due == nil && !$0.isCompleted }
        .map { apple -> AgendaItem in
            let (reminder, source) = appleReminderValue(apple, calendar: calendar)
            return AgendaItem(kind: .reminder(reminder), occurrence: .distantFuture, displayDate: .distantFuture,
                              isOverdue: false, appleSource: source)
        }
        .sorted { ($0.title, $0.id) < ($1.title, $1.id) }
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
