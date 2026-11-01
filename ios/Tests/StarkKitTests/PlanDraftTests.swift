import Testing
import Foundation
@testable import StarkKit

struct PlanDraftTests {
    let cal = Calendar(identifier: .gregorian)

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    var today: Date { at(2026, 11, 2, 10) }
    var day: Date { at(2026, 11, 3) }

    func model(reminders: [Reminder], events: [Event] = [], plans: [PlanBlock] = []) -> DayPlanModel {
        DayPlanModel.make(day: day, events: events, reminders: reminders, plans: plans, today: today)
    }
    func item(_ model: DayPlanModel, _ id: String) -> AgendaItem {
        (model.tray + model.timed).first {
            if case .reminder(let r) = $0.kind { return r.id == id } else { return false }
        }!
    }

    @Test func placeUsesDefaultThirty() {
        let r = Reminder(id: "a", title: "A", dueDate: at(2026, 10, 30, 9))
        let m = model(reminders: [r])
        var draft = PlanDraft(model: m)
        let ok1 = draft.place(item(m, "a"), at: at(2026, 11, 3, 9, 7))
        #expect(ok1)
        #expect(draft.blocks.count == 1)
        #expect(draft.blocks[0].minutes == 30)
        #expect(draft.blocks[0].start == at(2026, 11, 3, 9))
        #expect(draft.blocks[0].reminderID == "a")
        #expect(draft.blocks[0].occurrence == at(2026, 10, 30, 9))
    }

    @Test func placeEventIsRefused() {
        let e = Event(id: "e", title: "Meet", start: at(2026, 11, 3, 13), end: at(2026, 11, 3, 14))
        let m = model(reminders: [], events: [e])
        var draft = PlanDraft(model: m)
        let ok2 = draft.place(m.events[0], at: at(2026, 11, 3, 9))
        #expect(ok2 == false)
        #expect(draft.blocks.isEmpty)
    }

    @Test func movingTimedTaskCreatesBlockAndLeavesReminder() {
        let r = Reminder(id: "t", title: "T", dueDate: at(2026, 11, 3, 15))
        let before = r
        let m = model(reminders: [r])
        var draft = PlanDraft(model: m)
        let ok3 = draft.place(m.timed[0], at: at(2026, 11, 3, 10))
        #expect(ok3)
        #expect(draft.blocks.count == 1)
        #expect(draft.blocks[0].start == at(2026, 11, 3, 10))
        #expect(r == before)
        #expect(r.dueDate == at(2026, 11, 3, 15))
    }

    @Test func placingAlreadyPlacedItemMovesIt() {
        let r = Reminder(id: "a", title: "A", dueDate: at(2026, 10, 30, 9))
        let m = model(reminders: [r])
        var draft = PlanDraft(model: m)
        _ = draft.place(item(m, "a"), at: at(2026, 11, 3, 9))
        let ok4 = draft.place(item(m, "a"), at: at(2026, 11, 3, 11))
        #expect(ok4)
        #expect(draft.blocks.count == 1)
        #expect(draft.blocks[0].start == at(2026, 11, 3, 11))
    }

    @Test func removeReturnsToTray() {
        let r = Reminder(id: "a", title: "A", dueDate: at(2026, 10, 30, 9))
        let m0 = model(reminders: [r])
        var draft = PlanDraft(model: m0)
        _ = draft.place(item(m0, "a"), at: at(2026, 11, 3, 9))
        let planned = model(reminders: [r], plans: draft.blocks)
        #expect(planned.tray.isEmpty)
        draft.remove(id: draft.blocks[0].id)
        #expect(draft.blocks.isEmpty)
        let after = model(reminders: [r], plans: draft.blocks)
        #expect(after.tray.count == 1)
    }

    @Test func hasChangesFalseUntilEdited() {
        let r = Reminder(id: "a", title: "A", dueDate: at(2026, 10, 30, 9))
        let block = PlanBlock(id: "b", reminderID: "a", occurrence: at(2026, 10, 30, 9), start: at(2026, 11, 3, 9), minutes: 30)
        let m = model(reminders: [r], plans: [block])
        var draft = PlanDraft(model: m)
        #expect(draft.hasChanges == false)
        let ok5 = draft.move(id: "b", to: at(2026, 11, 3, 11))
        #expect(ok5)
        #expect(draft.hasChanges)
        let ok6 = draft.move(id: "b", to: at(2026, 11, 3, 9))
        #expect(ok6)
        #expect(draft.hasChanges == false)
        draft.resize(id: "b", toMinutes: 60)
        #expect(draft.hasChanges)
    }

    @Test func overlappingMoveIsShiftedToFreeSlot() {
        let r1 = Reminder(id: "a", title: "A", dueDate: at(2026, 10, 30, 9))
        let r2 = Reminder(id: "c", title: "C", dueDate: at(2026, 10, 30, 9))
        let b1 = PlanBlock(id: "b1", reminderID: "a", occurrence: at(2026, 10, 30, 9), start: at(2026, 11, 3, 9), minutes: 60)
        let b2 = PlanBlock(id: "b2", reminderID: "c", occurrence: at(2026, 10, 30, 9), start: at(2026, 11, 3, 12), minutes: 30)
        let m = model(reminders: [r1, r2], plans: [b1, b2])
        var draft = PlanDraft(model: m)
        let ok7 = draft.move(id: "b2", to: at(2026, 11, 3, 9, 15))
        #expect(ok7)
        let moved = draft.blocks.first { $0.id == "b2" }!
        let other = draft.blocks.first { $0.id == "b1" }!
        #expect(!(moved.start < other.end && other.start < moved.end))
        #expect(moved.start == at(2026, 11, 3, 8, 30))
        let ok8 = draft.move(id: "nope", to: at(2026, 11, 3, 9))
        #expect(ok8 == false)
    }

    @Test func resizeRespectsNeighbour() {
        let r1 = Reminder(id: "a", title: "A", dueDate: at(2026, 10, 30, 9))
        let r2 = Reminder(id: "c", title: "C", dueDate: at(2026, 10, 30, 9))
        let b1 = PlanBlock(id: "b1", reminderID: "a", occurrence: at(2026, 10, 30, 9), start: at(2026, 11, 3, 9), minutes: 30)
        let b2 = PlanBlock(id: "b2", reminderID: "c", occurrence: at(2026, 10, 30, 9), start: at(2026, 11, 3, 10), minutes: 30)
        let m = model(reminders: [r1, r2], plans: [b1, b2])
        var draft = PlanDraft(model: m)
        draft.resize(id: "b1", toMinutes: 180)
        #expect(draft.blocks.first { $0.id == "b1" }!.minutes == 60)
        draft.resize(id: "zzz", toMinutes: 15)
        #expect(draft.blocks.count == 2)
    }

    // MARK: Retained entries (saved blocks the model does not show)

    @Test func completedAndUnknownTaskBlocksAreRetainedOnSave() {
        let open = Reminder(id: "a", title: "A", dueDate: at(2026, 10, 30, 9))
        let done = Reminder(id: "d", title: "D", dueDate: at(2026, 11, 3, 8), isCompleted: true, completedDate: at(2026, 11, 3, 8))
        let visible = PlanBlock(id: "v", reminderID: "a", occurrence: at(2026, 10, 30, 9), start: at(2026, 11, 3, 9), minutes: 30)
        let completed = PlanBlock(id: "c", reminderID: "d", occurrence: at(2026, 11, 3, 8), start: at(2026, 11, 3, 13), minutes: 30)
        let unloaded = PlanBlock(id: "u", reminderID: "elsewhere", occurrence: at(2027, 2, 1, 9), start: at(2026, 11, 3, 15), minutes: 60)
        let saved = [visible, completed, unloaded]
        let m = model(reminders: [open, done], plans: saved)
        #expect(m.blocks.map(\.id) == ["v"])
        var draft = PlanDraft(model: m, saved: saved)
        #expect(draft.blocks.map(\.id) == ["v"])
        #expect(draft.hasChanges == false)
        #expect(Set(draft.blocksToSave.map(\.id)) == ["v", "c", "u"])
        // Removing the visible block removes it, the retained ones stay.
        draft.remove(id: "v")
        #expect(draft.hasChanges)
        #expect(Set(draft.blocksToSave.map(\.id)) == ["c", "u"])
    }

    @Test func retainedBlocksDoNotBlockPlacement() {
        let open = Reminder(id: "a", title: "A", dueDate: at(2026, 10, 30, 9))
        // A retained block for an unloaded task sits at 09:00-10:00.
        let unloaded = PlanBlock(id: "u", reminderID: "elsewhere", occurrence: at(2027, 2, 1, 9), start: at(2026, 11, 3, 9), minutes: 60)
        let m = model(reminders: [open], plans: [unloaded])
        var draft = PlanDraft(model: m, saved: [unloaded])
        let ok = draft.place(item(m, "a"), at: at(2026, 11, 3, 9))
        #expect(ok)
        #expect(draft.blocks.first { $0.reminderID == "a" }?.start == at(2026, 11, 3, 9))
        #expect(draft.blocksToSave.count == 2)
    }

    @Test func savedBlocksOnOtherDaysAreNotRetained() {
        let other = PlanBlock(id: "o", reminderID: "x", occurrence: at(2026, 11, 4, 9), start: at(2026, 11, 4, 9), minutes: 30)
        let m = model(reminders: [])
        let draft = PlanDraft(model: m, saved: [other])
        #expect(draft.blocksToSave.isEmpty)
    }
}
