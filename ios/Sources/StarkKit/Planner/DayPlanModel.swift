// ios/Sources/StarkKit/Planner/DayPlanModel.swift
import Foundation

/// What the day planner shows for one day: the tray of open tasks still to place, the tasks
/// already on the timeline at their own due time, that day's events, and the saved plan blocks
/// that still refer to an open task. Read-only: building it never changes a reminder or a plan.
public struct DayPlanModel {
    public let day: Date
    /// Open reminder rows not planned on `day` and not already timed on it, overdue first.
    public let tray: [AgendaItem]
    /// Open reminder rows due on `day` at a set time (not overdue, not 00:00) with no block.
    public let timed: [AgendaItem]
    /// Event rows on `day` that are all-day (shown in a banner above the timeline).
    public let allDayEvents: [AgendaItem]
    /// Event rows on `day` with a time (shown on the timeline).
    public let events: [AgendaItem]
    /// Plans starting on `day` whose reminder occurrence is still open. Others (deleted task,
    /// cleared carried miss, lapsed day) are left out here, not deleted from the store.
    public let blocks: [PlanBlock]

    /// - Reminder rows come from `buildAgendaItems` over `AgendaWindow.loadRange(around: day)`
    ///   (so a recurring series contributes only its single open row, or its next occurrence),
    ///   plus every open one-off whose due date lies outside that range (undated ones excluded).
    /// - A recurring series' row is in the tray only when it is overdue or falls on or before
    ///   `day`: its later next occurrence is not open yet.
    /// - A `day` before `today`'s day has lapsed: no tray, timed tasks or blocks.
    public static func make(
        day: Date, events: [Event], reminders: [Reminder], plans: [PlanBlock], today: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> DayPlanModel {
        let dayStart = calendar.startOfDay(for: day)
        let range = AgendaWindow.loadRange(around: day, calendar: calendar)
        let built = buildAgendaItems(events: events, reminders: reminders, in: range, today: today)

        func isOnDay(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: dayStart) }

        let eventItems = built.filter {
            if case .event = $0.kind { return isOnDay($0.displayDate) } else { return false }
        }
        let allDayEvents = eventItems.filter(isAllDayEvent)
        let timedEvents = eventItems.filter { !isAllDayEvent($0) }

        guard dayStart >= calendar.startOfDay(for: today) else {
            return DayPlanModel(day: day, tray: [], timed: [], allDayEvents: allDayEvents, events: timedEvents, blocks: [])
        }

        // Every open reminder row (the agenda's, plus one-offs outside its window).
        var open = built.filter { item in
            guard case .reminder(let r) = item.kind else { return false }
            return !r.isCompleted
        }
        let listed = Set(open.compactMap { item -> String? in
            if case .reminder(let r) = item.kind { return r.id } else { return nil }
        })
        let todayStart = calendar.startOfDay(for: today)
        for r in reminders where !r.isCompleted && r.recurrence == nil && !listed.contains(r.id) {
            // A one-off just past the load range's start can already be listed by the agenda's
            // overdue lookback (which counts from today, not from `day`): `listed` skips it.
            guard let due = r.dueDate, !range.contains(due) else { continue }
            open.append(AgendaItem(kind: .reminder(r), occurrence: due, displayDate: due,
                                   isOverdue: calendar.startOfDay(for: due) < todayStart))
        }

        func reminderID(_ item: AgendaItem) -> String? {
            if case .reminder(let r) = item.kind { return r.id } else { return nil }
        }
        func matches(_ plan: PlanBlock, _ item: AgendaItem) -> Bool {
            reminderID(item) == plan.reminderID && calendar.isDate(item.occurrence, inSameDayAs: plan.occurrence)
        }

        let blocks = plans
            .filter { plan in isOnDay(plan.start) && open.contains { matches(plan, $0) } }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        let unplanned = open.filter { item in !blocks.contains { matches($0, item) } }

        let timed = unplanned
            .filter { !$0.isOverdue && isOnDay($0.displayDate) && calendar.startOfDay(for: $0.displayDate) != $0.displayDate }
            .sorted { ($0.displayDate, $0.id) < ($1.displayDate, $1.id) }
        let timedIDs = Set(timed.map(\.id))
        let tray = unplanned
            .filter { item in
                guard !timedIDs.contains(item.id) else { return false }
                if item.isRecurring && !item.isOverdue {
                    return calendar.startOfDay(for: item.displayDate) <= dayStart
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue }
                return (lhs.occurrence, lhs.id) < (rhs.occurrence, rhs.id)
            }

        return DayPlanModel(day: day, tray: tray, timed: timed, allDayEvents: allDayEvents,
                            events: timedEvents, blocks: blocks)
    }

    private static func isAllDayEvent(_ item: AgendaItem) -> Bool {
        if case .event(let e) = item.kind { return e.isAllDay } else { return false }
    }
}
