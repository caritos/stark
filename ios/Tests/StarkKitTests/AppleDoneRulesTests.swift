import Testing
import Foundation
@testable import StarkKit

/// The "series moved past" and "completed copy" done rules apply only to REPEATING Apple
/// reminders (`AppleReminder.isRecurring`); a one-off reads like a local one-off.
struct AppleDoneRulesTests {
    let cal = Calendar(identifier: .gregorian)
    func at(_ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }
    let list = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: nil, isReminderList: true)

    func apple(_ id: String, _ title: String, due: Date?, done: Bool = false, repeating: Bool = false) -> AppleReminder {
        AppleReminder(id: id, title: title, notes: nil, due: due, dueHasTime: false, isCompleted: done,
                      completedAt: done ? due : nil, priority: nil, calendar: list, isRecurring: repeating)
    }
    /// A Nov 2 09:00 block for `apple-<id>`'s Nov 2 occurrence.
    func block(_ id: String) -> PlanBlock {
        PlanBlock(id: "b-\(id)", reminderID: "apple-\(id)", occurrence: at(11, 2), start: at(11, 2, 9), minutes: 30)
    }
    func history(_ reminders: [AppleReminder], today: Date) -> DayHistory {
        DayHistory.make(day: at(11, 2), events: [], reminders: [], plans: [], today: today,
                        apple: AppleSnapshot(events: [], reminders: reminders), sidecarPlans: [block("r1")], calendar: cal)
    }
    func planner(_ reminders: [AppleReminder]) -> DayPlanModel {
        DayPlanModel.make(day: at(11, 2), events: [], reminders: [], plans: [], today: at(11, 2, 8),
                          apple: AppleSnapshot(events: [], reminders: reminders), sidecarPlans: [block("r1")], calendar: cal)
    }

    @Test func isRecurringDefaultsToFalse() {
        let r = AppleReminder(id: "x", title: "X", notes: nil, due: nil, dueHasTime: false, isCompleted: false,
                              completedAt: nil, priority: nil, calendar: list)
        #expect(r.isRecurring == false)
    }

    @Test func oneOffMovedLaterIsMissedOnAPastDay() {
        // Same as a local one-off whose due date moved: still open, so MISSED on a past day.
        let h = history([apple("r1", "Post letter", due: at(11, 5))], today: at(11, 4, 10))
        #expect(h.done.isEmpty)
        #expect(h.open.map(\.title) == ["Post letter"])
        #expect(DayHistory.summaryLine(stats: h.stats, isToday: false) == "1 MISSED")
    }

    @Test func oneOffMovedLaterIsNeitherABlockNorDoneToday() {
        // Same as a local one-off: the block no longer matches its row, so it is not shown.
        let model = planner([apple("r1", "Post letter", due: at(11, 5))])
        #expect(model.blocks.isEmpty)
        #expect(model.doneBlocks.isEmpty)
        #expect(model.trayFuture.map(\.title) == ["Post letter"])
    }

    @Test func unrelatedCompletedReminderDoesNotCloseAnOpenOneOff() {
        let h = history([apple("r1", "Call Ana", due: at(11, 2)),
                         apple("other", "Call Ana", due: at(11, 2), done: true)], today: at(11, 4, 10))
        #expect(h.done.isEmpty)
        #expect(h.open.map(\.title) == ["Call Ana"])
    }

    @Test func repeatingSeriesStillReadsDone() {
        let moved = history([apple("r1", "Stretch", due: at(11, 9), repeating: true)], today: at(11, 4, 10))
        #expect(moved.done.map(\.title) == ["Stretch"])
        let copied = history([apple("r1", "Stretch", due: at(11, 2), repeating: true),
                              apple("c1", "Stretch", due: at(11, 2), done: true)], today: at(11, 4, 10))
        #expect(copied.done.map(\.title) == ["Stretch"])
        let today = planner([apple("r1", "Stretch", due: at(11, 3), repeating: true)])
        #expect(today.doneBlocks.map(\.title) == ["Stretch"])
    }
}
