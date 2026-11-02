import Testing
import Foundation
@testable import StarkKit

struct PlanSessionTests {
    let cal = Calendar(identifier: .gregorian)

    func at(_ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: min))!
    }
    var today: Date { at(4, 10) }

    func reminder(_ id: String) -> Reminder { Reminder(id: id, title: id, dueDate: at(1, 9)) }

    func model(_ day: Int, _ reminders: [Reminder] = [], plans: [PlanBlock] = []) -> DayPlanModel {
        DayPlanModel.make(day: at(day), events: [], reminders: reminders, plans: plans, today: today)
    }
    /// A draft for `day` that differs from its saved state.
    func changedDraft(_ day: Int, id: String = "a") -> PlanDraft {
        // A saved block removed again: a change that works for past days too.
        let saved = block(id, day: day)
        var draft = PlanDraft(model: model(day, [reminder(id)], plans: [saved]), saved: [saved])
        draft.remove(id: saved.id)
        return draft
    }
    func unchangedDraft(_ day: Int) -> PlanDraft { PlanDraft(model: model(day)) }
    func block(_ id: String, day: Int, hour: Int = 9) -> PlanBlock {
        PlanBlock(reminderID: id, occurrence: at(1, 9), start: at(day, hour), minutes: 30)
    }

    /// A draft for `day` holding one block that was moved off its saved start (non-empty, changed).
    func movedDraft(_ day: Int, id: String = "a") -> PlanDraft {
        let saved = block(id, day: day)
        var draft = PlanDraft(model: model(day, [reminder(id)], plans: [saved]), saved: [saved])
        _ = draft.move(id: saved.id, to: at(day, 14))
        return draft
    }

    @Test func stashAndRestore() {
        var session = PlanSession()
        let draft = movedDraft(6)
        #expect(!draft.blocks.isEmpty)
        #expect(draft.hasChanges)
        session.stash(draft, for: at(6, 10))
        let restored = session.draft(for: at(6))
        #expect(restored?.blocks == draft.blocks)
        #expect(restored?.blocksToSave == draft.blocksToSave)
        #expect(restored?.hasChanges == true)
        #expect(session.draft(for: at(7)) == nil)
    }

    @Test func changedDaysAscending() {
        var session = PlanSession()
        #expect(!session.hasChanges)
        session.stash(changedDraft(7), for: at(7))
        session.stash(unchangedDraft(5), for: at(5))
        session.stash(changedDraft(6), for: at(6))
        #expect(session.changedDays == [at(6), at(7)])
        #expect(session.hasChanges)
        var none = PlanSession()
        none.stash(unchangedDraft(5), for: at(5))
        #expect(!none.hasChanges)
    }

    @Test func dropLapsedRemovesPastDraftsOnly() {
        var session = PlanSession()
        session.stash(changedDraft(3), for: at(3))
        session.stash(changedDraft(5), for: at(5))
        session.dropLapsed(today: at(4))
        #expect(session.draft(for: at(3)) == nil)
        #expect(session.draft(for: at(5)) != nil)
    }

    @Test func plannedElsewhereUsesDraftOverSaved() {
        var session = PlanSession()
        let saved6 = block("s6", day: 6), saved7 = block("s7", day: 7), past = block("p", day: 2)
        session.stash(unchangedDraft(7), for: at(7))  // the day's block was removed in the draft
        let other = session.plannedElsewhere(of: at(5), saved: [saved6, saved7, past], today: today)
        #expect(other.contains(saved6))
        #expect(!other.contains(saved7))
        #expect(!other.contains(past))
        let own = session.plannedElsewhere(of: at(6), saved: [saved6, saved7, past], today: today)
        #expect(!own.contains(saved6))
    }

    @Test func plannedElsewhereReturnsNonEmptyDraftBlocksOfOtherDay() {
        var session = PlanSession()
        let draft = movedDraft(7)
        session.stash(draft, for: at(7))
        let other = session.plannedElsewhere(of: at(5), saved: [], today: today)
        #expect(!draft.blocks.isEmpty)
        for b in draft.blocksToSave { #expect(other.contains(b)) }
        let own = session.plannedElsewhere(of: at(7), saved: [], today: today)
        #expect(own.isEmpty)
    }

    @Test func saveAllWritesOnlyChangedEditableDays() {
        var session = PlanSession()
        session.stash(changedDraft(7), for: at(7))
        session.stash(changedDraft(3), for: at(3))
        session.stash(unchangedDraft(5), for: at(5))
        session.stash(changedDraft(6), for: at(6))
        var written: [Date] = []
        var blocks: [[PlanBlock]] = []
        let failed = session.saveAll(today: today) { day, b in written.append(day); blocks.append(b); return true }
        #expect(written == [at(6), at(7)])
        #expect(blocks.count == 2)
        #expect(blocks[0] == session.draft(for: at(6))!.blocksToSave)
        #expect(blocks[1] == session.draft(for: at(7))!.blocksToSave)
        #expect(failed.isEmpty)
    }

    @Test func saveAllReportsFailedDays() {
        var session = PlanSession()
        session.stash(changedDraft(6), for: at(6))
        session.stash(changedDraft(7), for: at(7))
        var written: [Date] = []
        let failed = session.saveAll(today: today) { day, _ in written.append(day); return day != self.at(6) }
        #expect(failed == [at(6)])
        #expect(written == [at(6), at(7)])
    }
}
