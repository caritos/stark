import Testing
import Foundation
@testable import StarkKit

struct DayPlanModelTests {
    let cal = Calendar(identifier: .gregorian)

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    /// "Now" is Monday Nov 2 2026, 10:00; the planned day is tomorrow.
    var today: Date { at(2026, 11, 2, 10) }
    var day: Date { at(2026, 11, 3) }

    func reminderIDs(_ items: [AgendaItem]) -> [String] {
        items.compactMap { if case .reminder(let r) = $0.kind { return r.id } else { return nil } }
    }

    func make(events: [Event] = [], reminders: [Reminder], plans: [PlanBlock] = [], day: Date? = nil) -> DayPlanModel {
        DayPlanModel.make(day: day ?? self.day, events: events, reminders: reminders, plans: plans, today: today)
    }

    @Test func trayHoldsOverdueFutureAndUndatedTimeOneOffs() {
        let overdue = Reminder(id: "overdue", title: "Call bank", dueDate: at(2026, 10, 30, 9))
        let later = Reminder(id: "later", title: "Renew passport", dueDate: at(2026, 11, 24, 14))
        let allDay = Reminder(id: "allday", title: "Groceries", dueDate: at(2026, 11, 3))
        let model = make(reminders: [overdue, later, allDay])
        #expect(reminderIDs(model.tray) == ["overdue", "allday", "later"])
        #expect(model.timed.isEmpty)
        let overdueItem = model.tray.first { reminderIDs([$0]) == ["overdue"] }
        #expect(overdueItem?.isOverdue == true)
        #expect(overdueItem?.occurrence == at(2026, 10, 30, 9))
    }

    @Test func oneOffsOutsideLoadRangeAreInTrayAndUndatedAreNot() {
        let ancient = Reminder(id: "ancient", title: "Old", dueDate: at(2026, 3, 1, 9))
        let farFuture = Reminder(id: "far", title: "Far", dueDate: at(2027, 6, 1))
        let undated = Reminder(id: "undated", title: "Someday")
        let model = make(reminders: [ancient, farFuture, undated])
        #expect(reminderIDs(model.tray) == ["ancient", "far"])
        let ancientItem = model.tray.first { reminderIDs([$0]) == ["ancient"] }
        #expect(ancientItem?.isOverdue == true)
        #expect(ancientItem?.occurrence == at(2026, 3, 1, 9))
        let farItem = model.tray.first { reminderIDs([$0]) == ["far"] }
        #expect(farItem?.isOverdue == false)
        #expect(farItem?.displayDate == at(2027, 6, 1))
    }

    @Test func oneOffAtLookbackEdgeAppearsOnce() {
        // 90 days before today is inside the agenda's overdue lookback but just outside the
        // load range around tomorrow: it must not be listed twice.
        let edge = Reminder(id: "edge", title: "Edge", dueDate: at(2026, 8, 4, 9))
        let model = make(reminders: [edge])
        #expect(reminderIDs(model.tray) == ["edge"])
    }

    @Test func timedTaskDueThatDayIsOnTimelineNotTray() {
        let timed = Reminder(id: "timed", title: "Dentist prep", dueDate: at(2026, 11, 3, 15))
        let model = make(reminders: [timed])
        #expect(reminderIDs(model.timed) == ["timed"])
        #expect(model.timed.first?.displayDate == at(2026, 11, 3, 15))
        #expect(model.tray.isEmpty)
    }

    @Test func recurringMissIsInTrayOnce() {
        // Daily at 08:00 from Oct 30: misses Oct 30, Oct 31 and Nov 1 (today's 10:00 is not a miss).
        let daily = Reminder(id: "daily", title: "Stretch", dueDate: at(2026, 10, 30, 8),
                             recurrence: RecurrenceRule(frequency: .daily))
        let model = make(reminders: [daily])
        #expect(reminderIDs(model.tray) == ["daily"])
        #expect(model.tray.first?.isOverdue == true)
        #expect(model.tray.first?.occurrence == at(2026, 10, 30, 8))
        // Tomorrow's 08:00 occurrence is not listed while the series is open.
        #expect(model.timed.isEmpty)
    }

    @Test func recurringTimedOccurrenceDueThatDayIsTimed() {
        let weekly = Reminder(id: "weekly", title: "Trash", dueDate: at(2026, 11, 3, 7, 30),
                              recurrence: RecurrenceRule(frequency: .weekly))
        let model = make(reminders: [weekly])
        #expect(reminderIDs(model.timed) == ["weekly"])
        #expect(model.timed.first?.occurrence == at(2026, 11, 3, 7, 30))
        #expect(model.tray.isEmpty)
    }

    @Test func recurringDateOnlyOccurrenceDueThatDayIsInTray() {
        let weekly = Reminder(id: "weekly", title: "Water plants", dueDate: at(2026, 11, 3),
                              recurrence: RecurrenceRule(frequency: .weekly))
        let model = make(reminders: [weekly])
        #expect(reminderIDs(model.tray) == ["weekly"])
        #expect(model.timed.isEmpty)
    }

    @Test func plannedTaskLeavesTray() {
        let overdue = Reminder(id: "overdue", title: "Call bank", dueDate: at(2026, 10, 30, 9))
        let timed = Reminder(id: "timed", title: "Dentist prep", dueDate: at(2026, 11, 3, 15))
        let other = Reminder(id: "other", title: "Groceries", dueDate: at(2026, 11, 3))
        let p1 = PlanBlock(id: "p1", reminderID: "overdue", occurrence: at(2026, 10, 30, 9), start: at(2026, 11, 3, 9), minutes: 30)
        let p2 = PlanBlock(id: "p2", reminderID: "timed", occurrence: at(2026, 11, 3, 15), start: at(2026, 11, 3, 11), minutes: 45)
        let model = make(reminders: [overdue, timed, other], plans: [p1, p2])
        #expect(reminderIDs(model.tray) == ["other"])
        #expect(model.timed.isEmpty)
        #expect(Set(model.blocks.map(\.id)) == ["p1", "p2"])
    }

    @Test func planOnAnotherDayIsNotABlock() {
        let task = Reminder(id: "t", title: "Task", dueDate: at(2026, 11, 3))
        let elsewhere = PlanBlock(id: "p", reminderID: "t", occurrence: at(2026, 11, 3), start: at(2026, 11, 4, 9), minutes: 30)
        let model = make(reminders: [task], plans: [elsewhere])
        #expect(model.blocks.isEmpty)
        #expect(reminderIDs(model.tray) == ["t"])
    }

    @Test func completedTaskNeverShown() {
        let doneThatDay = Reminder(id: "d1", title: "Done", dueDate: at(2026, 11, 3, 9), isCompleted: true,
                                   completedDate: at(2026, 11, 3, 9))
        let doneLongAgo = Reminder(id: "d2", title: "Ancient done", dueDate: at(2026, 1, 5), isCompleted: true,
                                   completedDate: at(2026, 1, 5))
        let doneFuture = Reminder(id: "d3", title: "Done early", dueDate: at(2027, 2, 1), isCompleted: true,
                                  completedDate: at(2027, 2, 1))
        let model = make(reminders: [doneThatDay, doneLongAgo, doneFuture])
        #expect(model.tray.isEmpty)
        #expect(model.timed.isEmpty)
    }

    @Test func orphanPlanIgnored() {
        // The carried miss (Oct 30) was completed: the store exdated every miss and today's own
        // occurrence and appended a completed copy, so the series' open item is now Nov 3.
        let daily = Reminder(id: "daily", title: "Stretch", dueDate: at(2026, 10, 30, 8),
                             recurrence: RecurrenceRule(frequency: .daily),
                             exceptionDates: [at(2026, 10, 30, 8), at(2026, 10, 31, 8), at(2026, 11, 1, 8), at(2026, 11, 2, 8)])
        let copy = Reminder(id: "copy", title: "Stretch", dueDate: at(2026, 10, 30, 8), isCompleted: true,
                            completedDate: at(2026, 10, 30, 8), seriesID: "daily")
        let cleared = PlanBlock(id: "cleared", reminderID: "daily", occurrence: at(2026, 10, 30, 8), start: at(2026, 11, 3, 9), minutes: 30)
        let gone = PlanBlock(id: "gone", reminderID: "deleted", occurrence: at(2026, 11, 3), start: at(2026, 11, 3, 10), minutes: 30)
        let model = make(reminders: [daily, copy], plans: [cleared, gone])
        #expect(model.blocks.isEmpty)
        // With no block, tomorrow's own 08:00 occurrence is back on the timeline.
        #expect(reminderIDs(model.timed) == ["daily"])
        #expect(model.timed.first?.occurrence == at(2026, 11, 3, 8))
    }

    @Test func lapsedPlanIgnored() {
        let yesterday = at(2026, 11, 1)
        let task = Reminder(id: "t", title: "Task", dueDate: at(2026, 10, 30, 9))
        let timed = Reminder(id: "timed", title: "Timed", dueDate: at(2026, 11, 1, 15))
        let plan = PlanBlock(id: "p", reminderID: "t", occurrence: at(2026, 10, 30, 9), start: at(2026, 11, 1, 9), minutes: 30)
        let model = make(reminders: [task, timed], plans: [plan], day: yesterday)
        #expect(model.blocks.isEmpty)
        #expect(model.tray.isEmpty)
        #expect(model.timed.isEmpty)
    }

    @Test func todayIsPlannable() {
        let task = Reminder(id: "t", title: "Task", dueDate: at(2026, 10, 30, 9))
        let plan = PlanBlock(id: "p", reminderID: "t", occurrence: at(2026, 10, 30, 9), start: at(2026, 11, 2, 14), minutes: 30)
        let model = make(reminders: [task], plans: [plan], day: at(2026, 11, 2))
        #expect(model.blocks.map(\.id) == ["p"])
        #expect(model.tray.isEmpty)
    }

    @Test func eventsSplitByAllDay() {
        let meeting = Event(id: "meeting", title: "Standup", start: at(2026, 11, 3, 9), end: at(2026, 11, 3, 9, 30))
        let holiday = Event(id: "holiday", title: "Holiday", start: at(2026, 11, 3), isAllDay: true)
        let otherDay = Event(id: "other", title: "Other", start: at(2026, 11, 4, 9))
        let model = make(events: [meeting, holiday, otherDay], reminders: [])
        func ids(_ items: [AgendaItem]) -> [String] {
            items.compactMap { if case .event(let e) = $0.kind { return e.id } else { return nil } }
        }
        #expect(ids(model.events) == ["meeting"])
        #expect(ids(model.allDayEvents) == ["holiday"])
        #expect(model.day == day)
    }

    @Test func skippedEventIsNotOnTheTimelineOrBanner() {
        let skippedAt = at(2026, 11, 3, 9)
        let skipped = Event(id: "skipped", title: "Church", start: skippedAt, end: at(2026, 11, 3, 10),
                            outcomes: [EventOutcomeRecord(date: skippedAt, outcome: .skipped)])
        let attended = Event(id: "attended", title: "Church 2", start: at(2026, 11, 3, 11), end: at(2026, 11, 3, 12),
                             outcomes: [EventOutcomeRecord(date: at(2026, 11, 3, 11), outcome: .attended)])
        let skippedAllDay = Event(id: "skippedAllDay", title: "Fair", start: at(2026, 11, 3), isAllDay: true,
                                  outcomes: [EventOutcomeRecord(date: at(2026, 11, 3), outcome: .skipped)])
        let plain = Event(id: "plain", title: "Standup", start: at(2026, 11, 3, 13), end: at(2026, 11, 3, 14))
        let model = make(events: [skipped, attended, skippedAllDay, plain], reminders: [])
        #expect(eventIDs(model.events) == ["plain", "attended"])
        #expect(model.allDayEvents.isEmpty)
    }

    @Test func skippingOneOccurrenceKeepsTheOtherDaysOfASeries() {
        let weekly = Event(id: "weekly", title: "Practice", start: at(2026, 11, 3, 9), end: at(2026, 11, 3, 10),
                           recurrence: RecurrenceRule(frequency: .daily),
                           outcomes: [EventOutcomeRecord(date: at(2026, 11, 3, 9), outcome: .skipped)])
        #expect(eventIDs(make(events: [weekly], reminders: [], day: at(2026, 11, 3)).events).isEmpty)
        #expect(eventIDs(make(events: [weekly], reminders: [], day: at(2026, 11, 4)).events) == ["weekly"])
    }

    func eventIDs(_ items: [AgendaItem]) -> [String] {
        items.compactMap { if case .event(let e) = $0.kind { return e.id } else { return nil } }
    }

    @Test func timedMultiDayEventIsInBannerOnEveryDay() {
        let trip = Event(id: "trip", title: "Conference", start: at(2026, 11, 2, 9), end: at(2026, 11, 5, 17))
        for d in [at(2026, 11, 2), at(2026, 11, 3), at(2026, 11, 5)] {
            let model = make(events: [trip], reminders: [], day: d)
            #expect(eventIDs(model.allDayEvents) == ["trip"])
            #expect(model.events.isEmpty)
        }
    }

    @Test func overnightEventIsInBannerOnBothDays() {
        let party = Event(id: "party", title: "Party", start: at(2026, 11, 2, 22), end: at(2026, 11, 3, 1))
        for d in [at(2026, 11, 2), at(2026, 11, 3)] {
            let model = make(events: [party], reminders: [], day: d)
            #expect(eventIDs(model.allDayEvents) == ["party"])
            #expect(model.events.isEmpty)
        }
    }

    @Test func eventEndingAtNextMidnightIsSingleDay() {
        let late = Event(id: "late", title: "Late show", start: at(2026, 11, 3, 22), end: at(2026, 11, 4))
        let model = make(events: [late], reminders: [], day: at(2026, 11, 3))
        #expect(eventIDs(model.events) == ["late"])
        #expect(model.events.first?.occurrence == at(2026, 11, 3, 22))
        #expect(model.allDayEvents.isEmpty)
        // It does not spill onto the next day at all.
        let next = make(events: [late], reminders: [], day: at(2026, 11, 4))
        #expect(next.events.isEmpty)
        #expect(next.allDayEvents.isEmpty)
    }

    @Test func dailyEventEndingAtMidnightIsListedOncePerDay() {
        let nightly = Event(id: "nightly", title: "Wind down", start: at(2026, 11, 1, 22), end: at(2026, 11, 2),
                            recurrence: RecurrenceRule(frequency: .daily))
        let model = make(events: [nightly], reminders: [], day: at(2026, 11, 3))
        #expect(eventIDs(model.events) == ["nightly"])
        #expect(model.allDayEvents.isEmpty)
    }

    @Test func singleDayTimedEventIsOnTimeline() {
        let lunch = Event(id: "lunch", title: "Lunch", start: at(2026, 11, 3, 12), end: at(2026, 11, 3, 13))
        let model = make(events: [lunch], reminders: [], day: at(2026, 11, 3))
        #expect(eventIDs(model.events) == ["lunch"])
        #expect(model.allDayEvents.isEmpty)
    }

    @Test func trayAndTimedAreOrdered() {
        let older = Reminder(id: "older", title: "A", dueDate: at(2026, 10, 20, 9))
        let newer = Reminder(id: "newer", title: "B", dueDate: at(2026, 10, 30, 9))
        let ancient = Reminder(id: "ancient", title: "C", dueDate: at(2026, 3, 1))
        let soon = Reminder(id: "soon", title: "D", dueDate: at(2026, 11, 3))
        let later = Reminder(id: "later", title: "E", dueDate: at(2026, 11, 24, 14))
        let far = Reminder(id: "far", title: "F", dueDate: at(2027, 6, 1))
        let afternoon = Reminder(id: "pm", title: "G", dueDate: at(2026, 11, 3, 15))
        let morning = Reminder(id: "am", title: "H", dueDate: at(2026, 11, 3, 8))
        let model = make(reminders: [far, later, soon, newer, ancient, older, afternoon, morning])
        #expect(reminderIDs(model.tray) == ["ancient", "older", "newer", "soon", "later", "far"])
        #expect(reminderIDs(model.timed) == ["am", "pm"])
    }

    // MARK: Tray panes (PAST | TODAY | FUTURE)

    @Test func panesWhenPlanningTomorrow() {
        let dueToday = Reminder(id: "dueToday", title: "Pay rent", dueDate: at(2026, 11, 2))
        let recent = Reminder(id: "recent", title: "Call bank", dueDate: at(2026, 10, 30, 9))
        let older = Reminder(id: "older", title: "Return book", dueDate: at(2026, 10, 20, 9))
        let ancient = Reminder(id: "ancient", title: "Old", dueDate: at(2026, 3, 1))
        let water = Reminder(id: "water", title: "Water plants", dueDate: at(2026, 11, 3))
        let groceries = Reminder(id: "groceries", title: "Groceries", dueDate: at(2026, 11, 3))
        let timed = Reminder(id: "timed", title: "Dentist prep", dueDate: at(2026, 11, 3, 15))
        let later = Reminder(id: "later", title: "Renew passport", dueDate: at(2026, 11, 24, 14))
        let soon = Reminder(id: "soon", title: "Book flights", dueDate: at(2026, 11, 4))
        let far = Reminder(id: "far", title: "Far", dueDate: at(2027, 6, 1))
        let model = make(reminders: [far, later, soon, timed, groceries, water, ancient, older, recent, dueToday])
        // A task due today is before the planned day (tomorrow): PAST, newest first.
        #expect(reminderIDs(model.trayPast) == ["dueToday", "recent", "older", "ancient"])
        // Same occurrence: by title.
        #expect(reminderIDs(model.trayToday) == ["groceries", "water"])
        #expect(reminderIDs(model.trayFuture) == ["soon", "later", "far"])
        #expect(reminderIDs(model.timed) == ["timed"])
        // `tray` is still every pane's item, nothing more, nothing less.
        #expect(Set(reminderIDs(model.tray)) == Set(reminderIDs(model.trayPast + model.trayToday + model.trayFuture)))
        #expect(model.tray.count == 9)
    }

    @Test func panesWhenPlanningToday() {
        let dueToday = Reminder(id: "dueToday", title: "Pay rent", dueDate: at(2026, 11, 2))
        let recent = Reminder(id: "recent", title: "Call bank", dueDate: at(2026, 10, 30, 9))
        let tomorrow = Reminder(id: "tomorrow", title: "Groceries", dueDate: at(2026, 11, 3))
        let model = make(reminders: [tomorrow, recent, dueToday], day: at(2026, 11, 2))
        #expect(reminderIDs(model.trayPast) == ["recent"])
        #expect(reminderIDs(model.trayToday) == ["dueToday"])
        #expect(reminderIDs(model.trayFuture) == ["tomorrow"])
    }

    @Test func todayPaneOrdersByTimeThenTitle() {
        // Tasks due on the day at a set time are on the timeline, so TODAY's are date-only and
        // their equal occurrence falls back to the title.
        let a = Reminder(id: "a", title: "Zebra", dueDate: at(2026, 11, 2))
        let b = Reminder(id: "b", title: "Apple", dueDate: at(2026, 11, 2))
        let model = make(reminders: [a, b], day: at(2026, 11, 2))
        #expect(reminderIDs(model.trayToday) == ["b", "a"])
    }

    @Test func overduePinnedRowUsesItsMissedOccurrence() {
        // Daily from Oct 30 08:00: the open row carries the Oct 30 miss, pinned to today's
        // section. Planning today, it is PAST (missed date), not TODAY (pinned display date).
        let daily = Reminder(id: "daily", title: "Stretch", dueDate: at(2026, 10, 30, 8),
                             recurrence: RecurrenceRule(frequency: .daily))
        let model = make(reminders: [daily], day: at(2026, 11, 2))
        #expect(reminderIDs(model.trayPast) == ["daily"])
        #expect(model.trayPast.first?.occurrence == at(2026, 10, 30, 8))
        #expect(model.trayToday.isEmpty)
        #expect(model.trayFuture.isEmpty)
    }

    @Test func emptyPanes() {
        let none = make(reminders: [])
        #expect(none.trayPast.isEmpty && none.trayToday.isEmpty && none.trayFuture.isEmpty && none.tray.isEmpty)
        let onlyFuture = make(reminders: [Reminder(id: "f", title: "F", dueDate: at(2026, 11, 20))])
        #expect(onlyFuture.trayPast.isEmpty)
        #expect(onlyFuture.trayToday.isEmpty)
        #expect(reminderIDs(onlyFuture.trayFuture) == ["f"])
        // A lapsed day has no tray at all.
        let lapsed = make(reminders: [Reminder(id: "o", title: "O", dueDate: at(2026, 10, 1))], day: at(2026, 11, 1))
        #expect(lapsed.trayPast.isEmpty && lapsed.trayToday.isEmpty && lapsed.trayFuture.isEmpty)
    }

    // MARK: Done blocks (completed planned tasks stay on the timeline)

    @Test func completedPlannedTasksAreDoneBlocks() {
        let planToday = at(2026, 11, 2)
        // A one-off completed in place.
        let oneOff = Reminder(id: "oneOff", title: "Write report", dueDate: at(2026, 11, 2, 9), isCompleted: true,
                              completedDate: at(2026, 11, 2, 9))
        // A recurring occurrence: the master is exdated and a completed copy carries seriesID.
        let daily = Reminder(id: "daily", title: "Stretch", dueDate: at(2026, 10, 30, 8),
                             recurrence: RecurrenceRule(frequency: .daily),
                             exceptionDates: [at(2026, 10, 30, 8), at(2026, 10, 31, 8), at(2026, 11, 1, 8), at(2026, 11, 2, 8)])
        let copy = Reminder(id: "copy", title: "Stretch", dueDate: at(2026, 11, 2, 8), isCompleted: true,
                            completedDate: at(2026, 11, 2, 8), seriesID: "daily")
        // An earlier completed copy of the same series must not match today's plan twice.
        let oldCopy = Reminder(id: "oldCopy", title: "Stretch", dueDate: at(2026, 10, 31, 8), isCompleted: true,
                               completedDate: at(2026, 10, 31, 8), seriesID: "daily")
        let open = Reminder(id: "open", title: "Open", dueDate: at(2026, 10, 30, 9))
        let pOneOff = PlanBlock(id: "pOneOff", reminderID: "oneOff", occurrence: at(2026, 11, 2, 9), start: at(2026, 11, 2, 13), minutes: 30)
        let pDaily = PlanBlock(id: "pDaily", reminderID: "daily", occurrence: at(2026, 11, 2, 8), start: at(2026, 11, 2, 9), minutes: 45)
        let pOpen = PlanBlock(id: "pOpen", reminderID: "open", occurrence: at(2026, 10, 30, 9), start: at(2026, 11, 2, 11), minutes: 30)
        let model = make(reminders: [oneOff, daily, copy, oldCopy, open], plans: [pOneOff, pDaily, pOpen, pDaily], day: planToday)
        #expect(model.doneBlocks.map(\.block.id) == ["pDaily", "pOneOff"])
        #expect(model.doneBlocks.map(\.title) == ["Stretch", "Write report"])
        #expect(model.doneCount == 2)
        #expect(model.blocks.map(\.id) == ["pOpen"])
    }

    @Test func notDoneBlocks() {
        let planToday = at(2026, 11, 2)
        let done = Reminder(id: "done", title: "Done", dueDate: at(2026, 11, 2), isCompleted: true, completedDate: at(2026, 11, 2))
        let unplanned = Reminder(id: "unplanned", title: "No plan", dueDate: at(2026, 11, 2), isCompleted: true,
                                 completedDate: at(2026, 11, 2))
        // A plan for the same task on another day is not a done block of this day.
        let otherDay = PlanBlock(id: "otherDay", reminderID: "done", occurrence: at(2026, 11, 2), start: at(2026, 11, 3, 9), minutes: 30)
        // A plan whose task was deleted.
        let orphan = PlanBlock(id: "orphan", reminderID: "deleted", occurrence: at(2026, 11, 2), start: at(2026, 11, 2, 9), minutes: 30)
        // A series plan whose completed copy is for a different occurrence day.
        let copy = Reminder(id: "copy", title: "Stretch", dueDate: at(2026, 11, 1, 8), isCompleted: true,
                            completedDate: at(2026, 11, 1, 8), seriesID: "series")
        let seriesPlan = PlanBlock(id: "seriesPlan", reminderID: "series", occurrence: at(2026, 11, 2, 8), start: at(2026, 11, 2, 10), minutes: 30)
        let model = make(reminders: [done, unplanned, copy], plans: [otherDay, orphan, seriesPlan], day: planToday)
        #expect(model.doneBlocks.isEmpty)
        #expect(model.doneCount == 0)
    }

    @Test func lapsedDayHasNoDoneBlocks() {
        let done = Reminder(id: "done", title: "Done", dueDate: at(2026, 11, 1), isCompleted: true, completedDate: at(2026, 11, 1))
        let plan = PlanBlock(id: "p", reminderID: "done", occurrence: at(2026, 11, 1), start: at(2026, 11, 1, 9), minutes: 30)
        #expect(make(reminders: [done], plans: [plan], day: at(2026, 11, 1)).doneBlocks.isEmpty)
    }

    @Test func summaryText() {
        #expect(DayPlanModel.summary(done: 3, planned: 2) == "3 DONE - 2 PLANNED")
        #expect(DayPlanModel.summary(done: 1, planned: 0) == "1 DONE")
        #expect(DayPlanModel.summary(done: 0, planned: 2) == nil)
        #expect(DayPlanModel.summary(done: 0, planned: 0) == nil)
    }
}
