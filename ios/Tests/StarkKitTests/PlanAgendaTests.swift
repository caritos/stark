// ios/Tests/StarkKitTests/PlanAgendaTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("PlanAgenda")
struct PlanAgendaTests {
    private let cal = Calendar(identifier: .gregorian)

    /// Fixed "now": Sunday 2026-09-20, 10:00 local.
    private var today: Date { dt("2026-09-20", hour: 10, minute: 0) }
    private var todayStart: Date { cal.startOfDay(for: today) }
    private var display: ClosedRange<Date> { AgendaWindow.range(around: today) }

    private func dt(_ iso: String, hour: Int, minute: Int) -> Date {
        let c = DateMath.components(iso)
        return cal.date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: hour, minute: minute))!
    }

    private func build(events: [Event] = [], reminders: [Reminder] = []) -> [AgendaItem] {
        buildAgendaItems(events: events, reminders: reminders, in: display, today: today)
    }

    @Test("an overdue task planned for tomorrow stays overdue today and also appears tomorrow at its planned time")
    func overdueTaskPlannedTomorrowAppearsOnBothDays() {
        let missedAt = dt("2026-09-19", hour: 9, minute: 0)
        let overdue = Reminder(id: "r", title: "Call bank", dueDate: missedAt)
        let later = Reminder(id: "later", title: "Later", dueDate: dt("2026-09-21", hour: 15, minute: 0))
        let meeting = Event(id: "e", title: "Meeting", start: dt("2026-09-21", hour: 10, minute: 0))
        let plan = PlanBlock(id: "p1", reminderID: "r", occurrence: missedAt,
                             start: dt("2026-09-21", hour: 14, minute: 0), minutes: 30)

        let items = build(events: [meeting], reminders: [overdue, later])
        let result = applyPlans(items, plans: [plan], today: today)

        #expect(result.count == 4)
        let todayRow = result[0]
        #expect(todayRow.displayDate == todayStart)
        #expect(todayRow.isOverdue)
        #expect(todayRow.plan == nil)
        #expect(todayRow.plannedRange == nil)
        #expect(todayRow.id == "r-\(missedAt.timeIntervalSince1970)")

        // Tomorrow: event 10:00, planned task 14:00, reminder 15:00.
        #expect(result[1].id == meeting.id + "-\(dt("2026-09-21", hour: 10, minute: 0).timeIntervalSince1970)")
        let planned = result[2]
        #expect(planned.displayDate == dt("2026-09-21", hour: 14, minute: 0))
        #expect(planned.occurrence == missedAt)
        #expect(planned.isOverdue)
        #expect(planned.plan == plan)
        #expect(planned.plannedRange == dt("2026-09-21", hour: 14, minute: 0)...dt("2026-09-21", hour: 14, minute: 30))
        #expect(planned.id == "r-\(missedAt.timeIntervalSince1970)-plan-p1")
        #expect(planned.id != todayRow.id)
        #expect(result[3].title == "Later")
    }

    @Test("a timed task planned on its own day is moved to the planned time, not duplicated")
    func timedTaskPlannedSameDayReplacesNotDuplicates() {
        let due = dt("2026-09-21", hour: 8, minute: 0)
        let task = Reminder(id: "r", title: "Write report", dueDate: due)
        let other = Reminder(id: "o", title: "Other", dueDate: dt("2026-09-21", hour: 11, minute: 0))
        let plan = PlanBlock(id: "p1", reminderID: "r", occurrence: due,
                             start: dt("2026-09-21", hour: 13, minute: 0), minutes: 60)

        let result = applyPlans(build(reminders: [task, other]), plans: [plan], today: today)

        #expect(result.count == 2)
        #expect(result.map(\.title) == ["Other", "Write report"])
        let planned = result[1]
        #expect(planned.displayDate == dt("2026-09-21", hour: 13, minute: 0))
        #expect(planned.occurrence == due)
        #expect(!planned.isOverdue)
        #expect(planned.plan == plan)
        #expect(planned.id == "r-\(due.timeIntervalSince1970)-plan-p1")
        #expect(task.dueDate == due)
    }

    @Test("a plan whose day has passed is ignored")
    func lapsedPlanIgnored() {
        let missedAt = dt("2026-09-18", hour: 9, minute: 0)
        let overdue = Reminder(id: "r", title: "Call bank", dueDate: missedAt)
        let plan = PlanBlock(id: "p1", reminderID: "r", occurrence: missedAt,
                             start: dt("2026-09-19", hour: 14, minute: 0), minutes: 30)

        let items = build(reminders: [overdue])
        let result = applyPlans(items, plans: [plan], today: today)

        #expect(result == items)
        #expect(result.count == 1)
        #expect(result[0].isOverdue)
        #expect(result[0].plan == nil)
    }

    @Test("a completed task gets no planned copy")
    func completedTaskHasNoPlannedCopy() {
        let due = dt("2026-09-21", hour: 9, minute: 0)
        let done = Reminder(id: "r", title: "Done", dueDate: due, isCompleted: true, completedDate: due)
        let plan = PlanBlock(id: "p1", reminderID: "r", occurrence: due,
                             start: dt("2026-09-21", hour: 13, minute: 0), minutes: 30)

        let items = build(reminders: [done])
        let result = applyPlans(items, plans: [plan], today: today)

        #expect(result == items)
        #expect(result.allSatisfy { $0.plan == nil })
    }

    @Test("a plan for another occurrence of the series, or naming an event, matches nothing")
    func planForOtherOccurrenceOrEventIgnored() {
        let due = dt("2026-09-21", hour: 9, minute: 0)
        let task = Reminder(id: "r", title: "Task", dueDate: due)
        let meeting = Event(id: "e", title: "Meeting", start: dt("2026-09-21", hour: 10, minute: 0))
        let wrongDay = PlanBlock(id: "p1", reminderID: "r", occurrence: dt("2026-09-22", hour: 9, minute: 0),
                                 start: dt("2026-09-21", hour: 13, minute: 0), minutes: 30)
        let onEvent = PlanBlock(id: "p2", reminderID: "e", occurrence: meeting.start,
                                start: dt("2026-09-21", hour: 15, minute: 0), minutes: 30)

        let items = build(events: [meeting], reminders: [task])
        #expect(applyPlans(items, plans: [wrongDay, onEvent], today: today) == items)
    }

    @Test("with no plans the output equals the input")
    func existingFixturesUnchangedWithoutPlans() {
        let daily = RecurrenceRule(frequency: .daily)
        let reminders = [
            Reminder(id: "a", title: "Overdue", dueDate: dt("2026-09-15", hour: 9, minute: 0)),
            Reminder(id: "b", title: "Daily", dueDate: dt("2026-09-10", hour: 7, minute: 0), recurrence: daily),
            Reminder(id: "c", title: "Done", dueDate: dt("2026-09-20", hour: 8, minute: 0), isCompleted: true,
                     completedDate: dt("2026-09-20", hour: 8, minute: 0)),
            Reminder(id: "d", title: "Future", dueDate: dt("2026-09-25", hour: 12, minute: 0)),
        ]
        let events = [
            Event(id: "e1", title: "Standup", start: dt("2026-09-14", hour: 9, minute: 30), recurrence: daily),
            Event(id: "e2", title: "Trip", start: cal.startOfDay(for: dt("2026-09-22", hour: 0, minute: 0)),
                  end: cal.startOfDay(for: dt("2026-09-24", hour: 0, minute: 0)), isAllDay: true),
        ]
        let items = build(events: events, reminders: reminders)
        #expect(!items.isEmpty)
        #expect(applyPlans(items, plans: [], today: today) == items)
    }

    @Test("a plan on a carried miss disappears once the miss is resolved")
    func planOnCarriedMissGoneAfterCompletion() {
        let daily = RecurrenceRule(frequency: .daily)
        let firstMiss = dt("2026-09-17", hour: 9, minute: 0)
        var master = Reminder(id: "r", title: "Stretch", dueDate: firstMiss, recurrence: daily)
        let plan = PlanBlock(id: "p1", reminderID: "r", occurrence: firstMiss,
                             start: dt("2026-09-21", hour: 8, minute: 0), minutes: 15)

        let before = applyPlans(build(reminders: [master]), plans: [plan], today: today)
        #expect(before.contains { $0.plan == plan })

        // Mirror PlannerStore.completeReminder: exdate the miss and every later miss up to today,
        // and add a completed one-off copy for the resolved occurrence.
        let after = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: firstMiss))!
        let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart)!.addingTimeInterval(-1)
        let later = OccurrenceExpander.expand(reminder: master, in: after...todayEnd)
        #expect(!later.isEmpty)
        master.exceptionDates.append(firstMiss)
        master.exceptionDates.append(contentsOf: later)
        var copy = master
        copy.id = "copy"
        copy.recurrence = nil
        copy.exceptionDates = []
        copy.isCompleted = true
        copy.completedDate = firstMiss
        copy.dueDate = firstMiss
        copy.seriesID = "r"

        let resolved = applyPlans(build(reminders: [master, copy]), plans: [plan], today: today)
        #expect(resolved.allSatisfy { $0.plan == nil })
    }

    @Test("an overdue row planned for today sorts at its planned time among the incomplete rows")
    func overdueRowPlannedTodaySortsByPlannedTime() {
        let missedAt = dt("2026-09-19", hour: 9, minute: 0)
        let overdue = Reminder(id: "r", title: "Overdue", dueDate: missedAt)
        let early = Reminder(id: "early", title: "Early", dueDate: dt("2026-09-20", hour: 8, minute: 0))
        let late = Reminder(id: "late", title: "Late", dueDate: dt("2026-09-20", hour: 17, minute: 0))
        let plan = PlanBlock(id: "p1", reminderID: "r", occurrence: missedAt,
                             start: dt("2026-09-20", hour: 12, minute: 0), minutes: 30)

        let result = applyPlans(build(reminders: [overdue, early, late]), plans: [plan], today: today)

        #expect(result.map(\.title) == ["Early", "Overdue", "Late"])
        #expect(result[1].isOverdue)
        #expect(result[1].plan == plan)
        #expect(result[1].displayDate == dt("2026-09-20", hour: 12, minute: 0))
    }

    // MARK: Tasks planned from outside the agenda window

    private func farPlan(_ reminderID: String, occurrence: Date) -> PlanBlock {
        PlanBlock(id: "pf", reminderID: reminderID, occurrence: occurrence,
                  start: dt("2026-09-21", hour: 14, minute: 0), minutes: 30)
    }

    @Test("a far-future one-off planned for tomorrow shows on tomorrow")
    func farFutureOneOffIsSynthesized() {
        let due = dt("2026-12-09", hour: 9, minute: 0) // +80 days
        let far = Reminder(id: "far", title: "Far", dueDate: due)
        let plan = farPlan("far", occurrence: due)
        let items = build(reminders: [far])
        #expect(items.isEmpty)
        let result = applyPlans(items, plans: [plan], today: today, reminders: [far])
        #expect(result.count == 1)
        #expect(result.first?.plan == plan)
        #expect(result.first?.occurrence == due)
        #expect(result.first?.displayDate == plan.start)
        #expect(result.first?.isOverdue == false)
    }

    @Test("a one-off overdue by more than 90 days planned for tomorrow shows as overdue")
    func longOverdueOneOffIsSynthesized() {
        let due = dt("2026-05-01", hour: 9, minute: 0)
        let old = Reminder(id: "old", title: "Old", dueDate: due)
        let plan = farPlan("old", occurrence: due)
        let items = build(reminders: [old])
        #expect(items.isEmpty)
        let result = applyPlans(items, plans: [plan], today: today, reminders: [old])
        #expect(result.count == 1)
        #expect(result.first?.isOverdue == true)
        #expect(result.first?.occurrence == due)
        #expect(result.first?.plan == plan)
    }

    @Test("completed, recurring, mismatched or missing reminders are not synthesized")
    func onlyOpenMatchingOneOffsAreSynthesized() {
        let due = dt("2026-12-09", hour: 9, minute: 0)
        let done = Reminder(id: "done", title: "Done", dueDate: due, isCompleted: true, completedDate: due)
        let series = Reminder(id: "series", title: "Series", dueDate: due, recurrence: RecurrenceRule(frequency: .weekly))
        let moved = Reminder(id: "moved", title: "Moved", dueDate: dt("2026-12-10", hour: 9, minute: 0))
        let plans = [
            PlanBlock(id: "a", reminderID: "done", occurrence: due, start: dt("2026-09-21", hour: 9, minute: 0), minutes: 30),
            PlanBlock(id: "b", reminderID: "series", occurrence: due, start: dt("2026-09-21", hour: 10, minute: 0), minutes: 30),
            PlanBlock(id: "c", reminderID: "moved", occurrence: due, start: dt("2026-09-21", hour: 11, minute: 0), minutes: 30),
            PlanBlock(id: "d", reminderID: "missing", occurrence: due, start: dt("2026-09-21", hour: 12, minute: 0), minutes: 30),
        ]
        let items = build(reminders: [done, moved])
        let result = applyPlans(items, plans: plans, today: today, reminders: [done, series, moved])
        #expect(result.allSatisfy { $0.plan == nil })
        #expect(result == items)
    }

    @Test("a lapsed plan for a far one-off is not synthesized")
    func lapsedFarPlanIgnored() {
        let due = dt("2026-12-09", hour: 9, minute: 0)
        let far = Reminder(id: "far", title: "Far", dueDate: due)
        let plan = PlanBlock(id: "p", reminderID: "far", occurrence: due, start: dt("2026-09-19", hour: 9, minute: 0), minutes: 30)
        #expect(applyPlans([], plans: [plan], today: today, reminders: [far]).isEmpty)
    }
}
