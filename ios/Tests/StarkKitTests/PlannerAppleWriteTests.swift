// ios/Tests/StarkKitTests/PlannerAppleWriteTests.swift
import Foundation
import Testing
@testable import StarkKit

/// Task 9b: the planner, Weekly Review, densities and undated display read and write Apple items.
@Suite("PlannerAppleWrite")
struct PlannerAppleWriteTests {
    let cal = Calendar(identifier: .gregorian)
    func at(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
    }
    let list = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: nil, isReminderList: true)

    func appleReminder(_ id: String, _ title: String = "Call", due: Date?) -> AppleReminder {
        AppleReminder(id: id, title: title, notes: nil, due: due, dueHasTime: due != nil, isCompleted: false,
                      completedAt: nil, priority: nil, calendar: list)
    }

    // MARK: Series-copy notice text

    @Test("the series-copy notice says what happened and where to reopen a separate reminder")
    func softenedNotice() {
        #expect(UncompleteNotice.message ==
            "This is a finished occurrence of a repeating reminder. The reminder already moved to its next date, so nothing was changed. If this was a separate reminder, reopen it in Reminders.")
    }

    // MARK: PlanSession async save (the router's replacePlans is async)

    func draft(day: Int) -> PlanDraft {
        let r = Reminder(id: "r\(day)", title: "R", dueDate: at(11, 1, 9))
        let saved = PlanBlock(reminderID: r.id, occurrence: at(11, 1, 9), start: at(11, day, 9), minutes: 30)
        let model = DayPlanModel.make(day: at(11, day), events: [], reminders: [r], plans: [saved], today: at(11, 4, 10))
        var draft = PlanDraft(model: model, saved: [saved])
        draft.remove(id: saved.id)
        return draft
    }

    @Test("async saveAll writes the changed editable days in order and reports the failed ones")
    func asyncSaveAll() async {
        var session = PlanSession()
        session.stash(draft(day: 7), for: at(11, 7))
        session.stash(draft(day: 3), for: at(11, 3))   // lapsed: never written
        session.stash(draft(day: 6), for: at(11, 6))
        let recorder = DayRecorder()
        let failed = await session.saveAll(today: at(11, 4, 10), writing: { day, blocks in
            await recorder.add(day, blocks)
            return day != self.at(11, 6)
        })
        #expect(await recorder.days == [at(11, 6), at(11, 7)])
        #expect(await recorder.blocks == [session.draft(for: at(11, 6))!.blocksToSave,
                                          session.draft(for: at(11, 7))!.blocksToSave])
        #expect(failed == [at(11, 6)])
    }

    actor DayRecorder {
        var days: [Date] = []
        var blocks: [[PlanBlock]] = []
        func add(_ day: Date, _ b: [PlanBlock]) { days.append(day); blocks.append(b) }
    }

    // MARK: Tray pane selection

    @Test("the NO DATE selection falls back to the day's own pane once that pane is gone")
    func paneFallsBack() {
        let withNoDate: [TrayPane] = [.past, .today, .future, .noDate]
        #expect(TrayPane.shown(.noDate, among: withNoDate) == .noDate)
        #expect(TrayPane.shown(.noDate, among: TrayPane.allCases) == .today)
        #expect(TrayPane.shown(.past, among: TrayPane.allCases) == .past)
        #expect(TrayPane.shown(.future, among: withNoDate) == .future)
    }

    @Test("an undated Apple reminder gives the planner a NO DATE pane; none gives three panes")
    func panesFollowUndated() {
        let today = at(11, 4, 10)
        let none = DayPlanModel.make(day: at(11, 4), events: [], reminders: [], plans: [], today: today)
        #expect(TrayPane.panes(for: none) == TrayPane.allCases)
        let apple = AppleSnapshot(events: [], reminders: [appleReminder("u1", due: nil)])
        let some = DayPlanModel.make(day: at(11, 4), events: [], reminders: [], plans: [], today: today, apple: apple)
        #expect(TrayPane.panes(for: some) == [.past, .today, .future, .noDate])
        // Planning it empties the pane again.
        let block = PlanBlock(reminderID: "apple-u1", occurrence: some.trayNoDate[0].occurrence,
                              start: at(11, 4, 9), minutes: 30)
        let planned = DayPlanModel.make(day: at(11, 4), events: [], reminders: [], plans: [], today: today,
                                        apple: apple, sidecarPlans: [block])
        #expect(planned.trayNoDate.isEmpty)
        #expect(planned.blocks == [block])
    }

    // MARK: The planner's plan inputs (each block once)

    @Test("the planner's plans are the sidecar's only, each once; a draft replaces the viewed day's")
    func plannerPlanInputs() {
        let day = at(11, 4)
        let appleToday = PlanBlock(id: "A1", reminderID: "apple-x", occurrence: day, start: at(11, 4, 11), minutes: 30)
        let appleOther = PlanBlock(id: "A2", reminderID: "apple-y", occurrence: day, start: at(11, 6, 11), minutes: 30)
        let apple = [appleToday, appleOther]

        // Saved: no draft blocks, the sidecar's blocks once.
        let saved = PlannerPlans.forModel(day: day, apple: apple, draftBlocks: nil, calendar: cal)
        #expect(saved.plans.isEmpty)
        #expect(saved.sidecarPlans == apple)

        // A draft replaces every saved block starting on the viewed day.
        let edited = PlanBlock(id: "N1", reminderID: "apple-z", occurrence: day, start: at(11, 4, 14), minutes: 30)
        let drafted = PlannerPlans.forModel(day: day, apple: apple, draftBlocks: [edited], calendar: cal)
        #expect(drafted.plans == [edited])
        #expect(drafted.sidecarPlans == [appleOther])

        // The draft's saved blocks are the viewed day's sidecar blocks, nothing else.
        #expect(PlannerPlans.saved(on: day, apple: apple, calendar: cal) == [appleToday])
    }

    // MARK: Densities count Apple plans

    @Test("an Apple reminder due outside the grid and planned onto a grid day counts on that day")
    func gridCountsApplePlan() {
        let today = at(6, 15, 10)
        let due = at(8, 2, 9)
        let apple = AppleSnapshot(events: [], reminders: [appleReminder("r1", due: due)])
        let plan = PlanBlock(reminderID: "apple-r1", occurrence: due, start: at(6, 20, 9), minutes: 30)
        let month = YearMonth(year: 2026, month0: 5)
        let grid = gridDensity(events: [], reminders: [], month: month, today: today, calendar: cal, plans: [plan], apple: apple)
        #expect(grid["2026-06-20"] == DayDensity(tasks: 1, events: 0))
        let year = yearDensity(events: [], reminders: [], year: 2026, today: today, calendar: cal, plans: [plan], apple: apple)
        #expect(year["2026-06-20"]?.tasks == 1)
        #expect(year["2026-08-02"]?.tasks == 1)
    }

    @Test("local-only densities are unchanged by the Apple path")
    func localDensityUnchanged() {
        let today = at(6, 15, 10)
        let r = Reminder(id: "r", title: "R", dueDate: at(8, 2, 9))
        let plan = PlanBlock(reminderID: "r", occurrence: at(8, 2, 9), start: at(6, 20, 9), minutes: 30)
        let grid = gridDensity(events: [], reminders: [r], month: YearMonth(year: 2026, month0: 5), today: today,
                               calendar: cal, plans: [plan])
        #expect(grid == ["2026-06-20": DayDensity(tasks: 1, events: 0)])
    }

    // MARK: Undated display

    func appleRow(due: Date?, occurrence: Date) -> AgendaItem {
        AgendaItem(kind: .reminder(Reminder(id: "apple-u", title: "U", dueDate: due)), occurrence: occurrence,
                   displayDate: occurrence, isOverdue: false,
                   appleSource: AppleSource(calendarID: "L1", calendarTitle: "Inbox", colorHex: nil, isReminder: true))
    }

    @Test("an undated Apple reminder reads No date instead of its sentinel; others use the formatter")
    func undatedText() {
        let fmt: (Date) -> String = { _ in "DATE" }
        #expect(appleRow(due: nil, occurrence: .distantPast).isUndatedApple)
        #expect(appleRow(due: nil, occurrence: .distantPast).dateText(fmt) == "No date")
        #expect(appleRow(due: nil, occurrence: .distantFuture).dateText(fmt) == "No date")
        #expect(appleRow(due: at(6, 1), occurrence: at(6, 1)).dateText(fmt) == "DATE")
        #expect(!appleRow(due: at(6, 1), occurrence: at(6, 1)).isUndatedApple)
        // A Stark reminder keeps its old text (local behaviour unchanged).
        let local = AgendaItem(kind: .reminder(Reminder(id: "L", title: "L", dueDate: nil)), occurrence: .distantPast,
                               displayDate: .distantPast, isOverdue: false)
        #expect(!local.isUndatedApple)
        #expect(local.dateText(fmt) == "DATE")
        #expect(AgendaItem.noDateText == "No date")
    }

    // MARK: The editor never invents a date for an undated reminder

    func undatedDetails() -> ItemDetails {
        ItemDetails(reminder: Reminder(id: "apple-u", title: "Undated", notes: "n", dueDate: nil),
                    dueHasTime: false, calendarID: "L1")
    }

    @Test("an undated reminder saved untouched keeps no due date: the patch is empty")
    func undatedUntouched() {
        let stored = undatedDetails()
        for occurrence in [Date.distantPast, .distantFuture] {
            let form = ItemEditForm(reminder: stored.reminder!, occurrence: occurrence)
            #expect(form.showsNoDate)
            let edited = form.edited(stored.reminder!)
            #expect(edited.dueDate == nil)
            #expect(ReminderPatch(from: stored.formBaseline(), to: edited, url: nil) == ReminderPatch())
        }
    }

    @Test("a title edit on an undated reminder patches only the title")
    func undatedTitleOnly() {
        let stored = undatedDetails()
        var form = ItemEditForm(reminder: stored.reminder!, occurrence: .distantPast)
        form.title = "Renamed"
        let patch = ReminderPatch(from: stored.formBaseline(), to: form.edited(stored.reminder!), url: nil)
        #expect(patch == ReminderPatch(title: "Renamed"))
    }

    @Test("adding a date to an undated reminder sets a date-only due on that day")
    func undatedAddDate() {
        let stored = undatedDetails()
        var form = ItemEditForm(reminder: stored.reminder!, occurrence: .distantPast)
        form.addDueDate(on: at(11, 15, 13, 20), calendar: cal)
        #expect(!form.showsNoDate)
        #expect(form.allDay)
        let edited = form.edited(stored.reminder!)
        #expect(edited.dueDate == at(11, 15))
        let patch = ReminderPatch(from: stored.formBaseline(), to: edited, url: nil)
        #expect(patch.due == .set(at(11, 15)))
    }

    @Test("a dated reminder never shows No date")
    func datedNeverNoDate() {
        let form = ItemEditForm(reminder: Reminder(id: "r", title: "R", dueDate: at(6, 1)), occurrence: at(6, 1))
        #expect(!form.showsNoDate)
    }

    // MARK: Fetch window screens

    @Test("the planner and Weekly Review widen the shared Apple fetch window while open")
    func plannerAndReviewScreens() {
        var window = AppleFetchWindow()
        window.set(.agenda, at(6, 1)...at(7, 1))
        window.set(.planner, at(9, 1)...at(9, 30))
        window.set(.weeklyReview, at(2, 1)...at(2, 7))
        #expect(window.covering == at(2, 1)...at(9, 30))
        window.set(.weeklyReview, nil)
        window.set(.planner, nil)
        #expect(window.covering == at(6, 1)...at(7, 1))
    }
}
