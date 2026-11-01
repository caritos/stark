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
        #expect(Set(reminderIDs(model.tray)) == ["overdue", "later", "allday"])
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
        #expect(Set(reminderIDs(model.tray)) == ["ancient", "far"])
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
}
