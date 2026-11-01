// ios/Sources/StarkKit/Planner/DayPlanModel.swift
import Foundation

/// What the day planner shows for one day: the tray of open tasks still to place, the tasks
/// already on the timeline at their own due time, that day's events, and the saved plan blocks
/// that still refer to an open task. Read-only: building it never changes a reminder or a plan.
public struct DayPlanModel {
    public let day: Date
    /// Open reminder rows not planned on `day` and not already timed on it: overdue first (by
    /// missed occurrence), then by occurrence. Rows from `buildAgendaItems` that are overdue have
    /// `displayDate` pinned to start-of-today; one-offs due outside the load range (far past or
    /// far future) keep their own due date as `displayDate`, even when overdue.
    public let tray: [AgendaItem]
    /// The tray split by each item's own `occurrence` (its missed date for an overdue row, never
    /// the pinned display date) against `day`, by calendar day: before `day`, newest first.
    public let trayPast: [AgendaItem]
    /// Tray items whose occurrence is on `day`, by occurrence then title.
    public let trayToday: [AgendaItem]
    /// Tray items whose occurrence is after `day`, soonest first.
    public let trayFuture: [AgendaItem]
    /// Open reminder rows due on `day` at a set time (not overdue, not 00:00) with no block.
    public let timed: [AgendaItem]
    /// Event rows on `day` that are all-day or multi-day (`isBannerEvent`), one per event, shown
    /// in a banner above the timeline.
    public let allDayEvents: [AgendaItem]
    /// Single-day timed event rows on `day` (shown on the timeline).
    public let events: [AgendaItem]
    /// Plans starting on `day` whose reminder occurrence is still open. Others (deleted task,
    /// cleared carried miss, lapsed day) are left out here, not deleted from the store.
    public let blocks: [PlanBlock]
    /// Plans starting on `day` whose task has been completed, by start: they stay on the
    /// timeline as read-only DONE blocks. A one-off matches by id (completed in place); a
    /// recurring occurrence matches its completed copy (`seriesID` = the plan's reminder id, due
    /// on the plan's occurrence day). Empty for a lapsed day.
    public let doneBlocks: [DoneBlock]
    public var doneCount: Int { doneBlocks.count }

    /// A plan block whose task is done, with the task's title.
    public struct DoneBlock: Equatable, Identifiable, Sendable {
        public let block: PlanBlock
        public let title: String
        public var id: String { block.id }
        public init(block: PlanBlock, title: String) {
            self.block = block
            self.title = title
        }
    }

    /// The planner header's count line, e.g. "3 DONE - 2 PLANNED" (a 0 part is left out);
    /// nil when nothing is done.
    public static func summary(done: Int, planned: Int) -> String? {
        guard done > 0 else { return nil }
        return planned > 0 ? "\(done) DONE - \(planned) PLANNED" : "\(done) DONE"
    }

    init(day: Date, tray: [AgendaItem], timed: [AgendaItem], allDayEvents: [AgendaItem],
         events: [AgendaItem], blocks: [PlanBlock], doneBlocks: [DoneBlock] = [],
         calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.day = day
        self.doneBlocks = doneBlocks
        self.tray = tray
        self.timed = timed
        self.allDayEvents = allDayEvents
        self.events = events
        self.blocks = blocks
        let dayStart = calendar.startOfDay(for: day)
        func occurrenceDay(_ item: AgendaItem) -> Date { calendar.startOfDay(for: item.occurrence) }
        func ascending(_ lhs: AgendaItem, _ rhs: AgendaItem) -> Bool {
            (lhs.occurrence, lhs.title, lhs.id) < (rhs.occurrence, rhs.title, rhs.id)
        }
        trayPast = tray.filter { occurrenceDay($0) < dayStart }.sorted {
            ($1.occurrence, $0.title, $0.id) < ($0.occurrence, $1.title, $1.id)
        }
        trayToday = tray.filter { occurrenceDay($0) == dayStart }.sorted(by: ascending)
        trayFuture = tray.filter { occurrenceDay($0) > dayStart }.sorted(by: ascending)
    }

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

        // An occurrence the user marked Skip (didn't attend) takes no time, so it is neither on the
        // timeline nor in the banner and its slot reads as free (issue #117). Attended ones stay.
        let eventItems = built.filter {
            if case .event = $0.kind { return isOnDay($0.displayDate) && $0.outcome != .skipped } else { return false }
        }
        var bannerSeen = Set<String>()
        let allDayEvents = eventItems.filter { item in
            guard case .event(let e) = item.kind, isBannerEvent(e, calendar: calendar) else { return false }
            return bannerSeen.insert(e.id).inserted
        }
        var timelineSeen = Set<String>()
        let timedEvents = eventItems.filter { item in
            guard case .event(let e) = item.kind, !isBannerEvent(e, calendar: calendar) else { return false }
            // An event ending exactly at the next midnight gets a spurious second-day row from
            // `buildAgendaItems` (its span is 1): keep only rows that are real occurrences.
            if spanDays(of: e, calendar: calendar) > 0,
               OccurrenceExpander.expand(event: e, in: item.occurrence...item.occurrence).isEmpty { return false }
            return timelineSeen.insert(item.id).inserted
        }

        guard dayStart >= calendar.startOfDay(for: today) else {
            return DayPlanModel(day: day, tray: [], timed: [], allDayEvents: allDayEvents, events: timedEvents, blocks: [], calendar: calendar)
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

        // Completed tasks' plans on this day (never one already shown as an open block).
        let blockIDs = Set(blocks.map(\.id))
        var doneSeen = Set<String>()
        let doneBlocks = plans
            .filter { isOnDay($0.start) && !blockIDs.contains($0.id) }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
            .compactMap { plan -> DoneBlock? in
                guard let done = doneBlock(for: plan, reminders: reminders, calendar: calendar),
                      doneSeen.insert(plan.id).inserted else { return nil }
                return done
            }

        return DayPlanModel(day: day, tray: tray, timed: timed, allDayEvents: allDayEvents,
                            events: timedEvents, blocks: blocks, doneBlocks: doneBlocks, calendar: calendar)
    }

    /// The plan as a done block when its task is completed: a one-off by id, a recurring
    /// occurrence by its completed copy (`seriesID` = the plan's reminder id, due on the plan's
    /// occurrence day). nil when no completed reminder matches.
    static func doneBlock(for plan: PlanBlock, reminders: [Reminder], calendar: Calendar) -> DoneBlock? {
        let match = reminders.first { r in
            guard r.isCompleted else { return false }
            if r.id == plan.reminderID { return true }
            guard r.seriesID == plan.reminderID, let due = r.dueDate ?? r.completedDate else { return false }
            return calendar.isDate(due, inSameDayAs: plan.occurrence)
        }
        return match.map { DoneBlock(block: plan, title: $0.title) }
    }

    /// Banner, not timeline: an all-day event, or a multi-day one, i.e. its end falls on a later
    /// calendar day than its start (`spanDays`, the agenda's own span rule). An end at exactly
    /// 00:00 of the day after the start does not count: 22:00-24:00 is a single-day event.
    static func isBannerEvent(_ event: Event, calendar: Calendar) -> Bool {
        if event.isAllDay { return true }
        let span = spanDays(of: event, calendar: calendar)
        guard span == 1, let end = event.end else { return span > 1 }
        return end != calendar.startOfDay(for: end)
    }
}
