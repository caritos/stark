// ios/Tests/StarkKitTests/PlannerAppleWriteFixTests.swift
import Foundation
import Testing
@testable import StarkKit

/// Task 9b fix round 1: late edits during a save are kept; a planned undated Apple reminder
/// appears on its planned day.
@Suite("PlannerAppleWriteFix")
struct PlannerAppleWriteFixTests {
    let cal = Calendar(identifier: .gregorian)
    func at(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
    }
    let list = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: nil, isReminderList: true)

    func apple(_ id: String, _ title: String, due: Date? = nil, done: Bool = false) -> AppleReminder {
        AppleReminder(id: id, title: title, notes: nil, due: due, dueHasTime: due != nil, isCompleted: done,
                      completedAt: done ? at(11, 10) : nil, priority: nil, calendar: list)
    }

    // MARK: 1. A save never discards edits made while it was writing

    var today: Date { at(11, 4, 10) }

    func session(movingTo hour: Int?) -> PlanSession {
        let r = Reminder(id: "r", title: "R", dueDate: at(11, 4, 8))
        let saved = PlanBlock(id: "B", reminderID: "r", occurrence: at(11, 4, 8), start: at(11, 4, 9), minutes: 30)
        let model = DayPlanModel.make(day: at(11, 4), events: [], reminders: [r], plans: [saved], today: today)
        var draft = PlanDraft(model: model, saved: [saved])
        _ = draft.move(id: "B", to: at(11, 4, 14))
        if let hour { _ = draft.move(id: "B", to: at(11, 4, hour)) }
        var s = PlanSession()
        s.stash(draft, for: at(11, 4))
        return s
    }

    @Test("the planner may close when the live drafts are what was written")
    func sameDraftsDismiss() {
        let written = session(movingTo: nil)
        #expect(!written.hasEdits(since: written, today: today))
        #expect(!session(movingTo: nil).hasEdits(since: written, today: today))
    }

    @Test("a block moved while the save was writing keeps the planner open")
    func lateMoveStaysOpen() {
        let written = session(movingTo: nil)
        let live = session(movingTo: 16)
        #expect(live.hasEdits(since: written, today: today))
    }

    @Test("a day first edited while the save was writing keeps the planner open")
    func lateNewDayStaysOpen() {
        let written = session(movingTo: nil)
        var live = written
        let model = DayPlanModel.make(day: at(11, 5), events: [], reminders: [Reminder(id: "x", title: "X", dueDate: at(11, 5))],
                                      plans: [], today: today)
        var draft = PlanDraft(model: model)
        let placed = draft.place(model.tray[0], at: at(11, 5, 9))
        #expect(placed)
        live.stash(draft, for: at(11, 5))
        #expect(live.hasEdits(since: written, today: today))
    }

    // MARK: 2. A planned undated Apple reminder appears on its planned day

    var undatedPlan: PlanBlock {
        PlanBlock(id: "P", reminderID: "apple-u1", occurrence: .distantFuture, start: at(11, 6, 9), minutes: 30)
    }
    var range: ClosedRange<Date> { at(11, 1)...at(11, 30, 23, 59) }

    @Test("a planned undated Apple reminder is a planned row on its planned day")
    func plannedUndatedAppears() {
        let snap = AppleSnapshot(events: [], reminders: [apple("u1", "Call bank")])
        let rows = agendaWithApple(local: [], snapshot: snap, plans: [undatedPlan], range: range, today: today)
        #expect(rows.count == 1)
        guard let row = rows.first else { return }
        #expect(row.title == "Call bank")
        #expect(row.plan == undatedPlan)
        #expect(row.displayDate == at(11, 6, 9))
        #expect(row.occurrence == .distantFuture)
        #expect(!row.isOverdue)
        #expect(row.appleSource?.calendarID == "L1")
        guard case .reminder(let r) = row.kind else { Issue.record("not a reminder"); return }
        #expect(r.id == "apple-u1" && r.dueDate == nil)
    }

    @Test("an unplanned undated reminder stays out of the agenda; a completed one is not resurrected by its plan")
    func unplannedAndCompletedStayOut() {
        let open = AppleSnapshot(events: [], reminders: [apple("u1", "Call bank")])
        #expect(agendaWithApple(local: [], snapshot: open, plans: [], range: range, today: today).isEmpty)
        let done = AppleSnapshot(events: [], reminders: [apple("u1", "Call bank", done: true)])
        #expect(agendaWithApple(local: [], snapshot: done, plans: [undatedPlan], range: range, today: today).isEmpty)
    }

    @Test("two undated reminders with the same title match by id, never by title")
    func matchesByID() {
        let snap = AppleSnapshot(events: [], reminders: [apple("u1", "Call bank"), apple("u2", "Call bank")])
        let rows = agendaWithApple(local: [], snapshot: snap, plans: [undatedPlan], range: range, today: today)
        #expect(rows.count == 1)
        guard case .reminder(let r) = rows.first?.kind else { Issue.record("no row"); return }
        #expect(r.id == "apple-u1")
    }

    @Test("a plan whose occurrence is a real day never matches an undated reminder")
    func datedPlanDoesNotMatchUndated() {
        let snap = AppleSnapshot(events: [], reminders: [apple("u1", "Call bank")])
        var plan = undatedPlan
        plan.occurrence = at(11, 6)
        #expect(agendaWithApple(local: [], snapshot: snap, plans: [plan], range: range, today: today).isEmpty)
    }

    @Test("the month grid and the day density count a planned undated reminder on its planned day")
    func densitiesCountIt() {
        let snap = AppleSnapshot(events: [], reminders: [apple("u1", "Call bank")])
        let month = YearMonth(year: 2026, month0: 10)
        let grid = gridDensity(events: [], reminders: [], month: month, today: today, calendar: cal,
                               plans: [undatedPlan], apple: snap)
        #expect(grid == ["2026-11-06": DayDensity(tasks: 1, events: 0)])
        let days = dayDensity(events: [], reminders: [], month: month, today: today, calendar: cal,
                              apple: snap, plans: [undatedPlan])
        #expect(days == [6: DayDensity(tasks: 1, events: 0)])
        // Unplanned: counted nowhere.
        #expect(gridDensity(events: [], reminders: [], month: month, today: today, calendar: cal, apple: snap).isEmpty)
    }

    @Test("a planned undated reminder's row has no sentinel 'due' line")
    func undatedPlanRowHasNoDueLine() {
        let start = at(11, 6, 9)
        let lines = PlanRowText.make(occurrence: .distantFuture, overdueText: nil,
                                     range: start...start.addingTimeInterval(1800),
                                     time: { _ in "T" }, monthDay: { _ in "MD" })
        #expect(lines.primary == "T - T")
        #expect(lines.secondary == nil)
    }

    @Test("local planned items are unchanged")
    func localUnchanged() {
        let r = Reminder(id: "r", title: "R", dueDate: at(11, 20, 9))
        let plan = PlanBlock(id: "LP", reminderID: "r", occurrence: at(11, 20, 9), start: at(11, 6, 9), minutes: 30)
        let local = buildAgendaItems(events: [], reminders: [r], in: range, today: today)
        let before = applyPlans(local, plans: [plan], today: today, reminders: [r])
        let after = agendaWithApple(local: local, snapshot: .empty, plans: [plan], range: range, today: today, reminders: [r])
        #expect(before == after)
        #expect(after.count == 2)
    }
}
