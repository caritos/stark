import Testing
import Foundation
@testable import StarkKit

struct PlanDraftCompleteTests {
    let cal = Calendar(identifier: .gregorian)
    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    var today: Date { at(2026, 11, 2, 8) }
    var day: Date { at(2026, 11, 2) }

    func block(_ id: String, _ r: String, _ h: Int, occ: Date? = nil) -> PlanBlock {
        PlanBlock(id: id, reminderID: r, occurrence: occ ?? at(2026, 11, 2), start: at(2026, 11, 2, h), minutes: 30)
    }
    func make(_ reminders: [Reminder], plans: [PlanBlock]) -> DayPlanModel {
        DayPlanModel.make(day: day, events: [], reminders: reminders, plans: plans, today: today)
    }

    @Test func completingKeepsOtherUnsavedEdits() {
        let a = Reminder(id: "a", title: "A", dueDate: at(2026, 11, 2))
        let b = Reminder(id: "b", title: "B", dueDate: at(2026, 11, 2))
        let plans = [block("pa", "a", 9), block("pb", "b", 11)]
        var draft = PlanDraft(model: make([a, b], plans: plans), saved: plans)
        let moved = draft.move(id: "pb", to: at(2026, 11, 2, 14))
        #expect(moved)
        let done = draft.markDone(id: "pa")
        #expect(done?.reminderID == "a")
        #expect(draft.blocks.map(\.id) == ["pb"])
        #expect(draft.blocks[0].start == at(2026, 11, 2, 14))
        #expect(draft.done.map(\.id) == ["pa"])
        #expect(draft.hasChanges)
    }

    @Test func saveAfterCompletingKeepsExactlyOneEntry() {
        let a = Reminder(id: "a", title: "A", dueDate: at(2026, 11, 2))
        let plans = [block("pa", "a", 9)]
        var draft = PlanDraft(model: make([a], plans: plans), saved: plans)
        draft.markDone(id: "pa")
        #expect(draft.blocksToSave.map(\.id) == ["pa"])
        var completed = a
        completed.isCompleted = true
        completed.completedDate = at(2026, 11, 2)
        let rebuilt = make([completed], plans: draft.blocksToSave)
        #expect(rebuilt.blocks.isEmpty)
        #expect(rebuilt.doneBlocks.map(\.id) == ["pa"])
        let again = draft.markDone(id: "pa")
        #expect(again == nil)
        #expect(draft.blocksToSave.map(\.id) == ["pa"])
    }

    @Test func completingAnUnsavedPlacementCountsAndBlocksTheSlot() {
        let a = Reminder(id: "a", title: "A", dueDate: at(2026, 11, 2))
        let m = make([a], plans: [])
        var draft = PlanDraft(model: m)
        let ok = draft.place(m.tray[0], at: at(2026, 11, 2, 9))
        #expect(ok)
        draft.markDone(id: draft.blocks[0].id)
        #expect(draft.blocks.isEmpty)
        #expect(draft.hasChanges)
        #expect(draft.blocksToSave.count == 1)
        let other = PlanBlock(id: "x", reminderID: "b", occurrence: at(2026, 11, 2), start: at(2026, 11, 2, 9), minutes: 30)
        let placed = PlanLayout.place(other, among: draft.done, day: day)
        #expect(placed?.start != at(2026, 11, 2, 9))
    }

    @Test func completingARecurringOccurrenceBlock() {
        var daily = Reminder(id: "r", title: "Daily", dueDate: at(2026, 11, 2, 7))
        daily.recurrence = RecurrenceRule(frequency: .daily)
        let plans = [block("pr", "r", 9, occ: at(2026, 11, 2, 7))]
        var draft = PlanDraft(model: make([daily], plans: plans), saved: plans)
        let done = draft.markDone(id: "pr")
        #expect(done?.occurrence == at(2026, 11, 2, 7))
        #expect(draft.blocks.isEmpty)
        #expect(draft.blocksToSave.map(\.id) == ["pr"])
    }
}
