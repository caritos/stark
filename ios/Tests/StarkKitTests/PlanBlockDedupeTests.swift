import Testing
import Foundation
@testable import StarkKit

/// `ItemRouter.plans(on:)` returns local AND Apple blocks, so a caller may pass the same blocks as
/// both `plans` and `sidecarPlans`: each block id counts once.
struct PlanBlockDedupeTests {
    let cal = Calendar(identifier: .gregorian)
    func at(_ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }
    let list = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: nil, isReminderList: true)
    var local: Reminder { Reminder(id: "l1", title: "Local", dueDate: at(11, 2)) }
    var snapshot: AppleSnapshot {
        AppleSnapshot(events: [], reminders: [
            AppleReminder(id: "a1", title: "Apple open", notes: nil, due: at(11, 2), dueHasTime: false,
                          isCompleted: false, completedAt: nil, priority: nil, calendar: list),
            AppleReminder(id: "a2", title: "Apple done", notes: nil, due: at(11, 2), dueHasTime: false,
                          isCompleted: true, completedAt: at(11, 2, 8), priority: nil, calendar: list),
        ])
    }
    var blocks: [PlanBlock] {
        [PlanBlock(id: "p-l1", reminderID: "l1", occurrence: at(11, 2), start: at(11, 2, 9), minutes: 30),
         PlanBlock(id: "p-a1", reminderID: "apple-a1", occurrence: at(11, 2), start: at(11, 2, 10), minutes: 30),
         PlanBlock(id: "p-a2", reminderID: "apple-a2", occurrence: at(11, 2), start: at(11, 2, 11), minutes: 30)]
    }

    @Test func plannerCountsEachBlockOnce() {
        let today = at(11, 2, 8)
        let once = DayPlanModel.make(day: at(11, 2), events: [], reminders: [local], plans: blocks, today: today,
                                     apple: snapshot, calendar: cal)
        let twice = DayPlanModel.make(day: at(11, 2), events: [], reminders: [local], plans: blocks, today: today,
                                      apple: snapshot, sidecarPlans: blocks, calendar: cal)
        #expect(once.blocks.map(\.id) == ["p-l1", "p-a1"])
        #expect(twice.blocks == once.blocks)
        #expect(twice.doneBlocks == once.doneBlocks)
        #expect(twice.doneBlocks.map(\.id) == ["p-a2"])
    }

    @Test func historyAndWeekStatsCountEachBlockOnce() {
        let today = at(11, 4, 10)
        let once = DayHistory.make(day: at(11, 2), events: [], reminders: [local], plans: blocks, today: today,
                                   apple: snapshot, calendar: cal)
        let twice = DayHistory.make(day: at(11, 2), events: [], reminders: [local], plans: blocks, today: today,
                                    apple: snapshot, sidecarPlans: blocks, calendar: cal)
        #expect(once.stats == DayHistory.Stats(done: 1, open: 2, plannedMinutes: 90, doneMinutes: 30))
        #expect(twice.stats == once.stats)
        #expect(twice.done == once.done && twice.open == once.open)
        let weekOnce = DayHistory.weekStats(containing: at(11, 2), reminders: [local], plans: blocks, today: today,
                                            apple: snapshot, calendar: cal)
        let weekTwice = DayHistory.weekStats(containing: at(11, 2), reminders: [local], plans: blocks, today: today,
                                             apple: snapshot, sidecarPlans: blocks, calendar: cal)
        #expect(weekTwice == weekOnce)
        #expect(weekOnce.done + weekOnce.open == 3)
    }
}
