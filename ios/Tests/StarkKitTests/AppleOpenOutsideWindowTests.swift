import Testing
import Foundation
@testable import StarkKit

/// The provider keeps EVERY open reminder in the snapshot (any due date). One due outside the
/// window must not change the agenda, yet must let the planner read an earlier block as done.
struct AppleOpenOutsideWindowTests {
    let cal = Calendar(identifier: .gregorian)
    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    let list = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: nil, isReminderList: true)

    /// A yearly "Renew insurance" completed for Nov 2 2026: the series now reads due Nov 2 2027,
    /// and Apple left a completed copy due Nov 2 2026.
    var series: AppleReminder {
        AppleReminder(id: "y1", title: "Renew insurance", notes: nil, due: at(2027, 11, 2), dueHasTime: false,
                      isCompleted: false, completedAt: nil, priority: nil, calendar: list, isRecurring: true)
    }
    var copy: AppleReminder {
        AppleReminder(id: "copy", title: "Renew insurance", notes: nil, due: at(2026, 11, 2), dueHasTime: false,
                      isCompleted: true, completedAt: at(2026, 11, 2, 9), priority: nil, calendar: list)
    }
    var today: Date { at(2026, 11, 4, 10) }
    var block: PlanBlock {
        PlanBlock(id: "b1", reminderID: "apple-y1", occurrence: at(2026, 11, 2), start: at(2026, 11, 2, 9), minutes: 30)
    }

    @Test func openReminderOutsideTheWindowDoesNotChangeTheAgenda() {
        let range = AgendaWindow.range(around: today, calendar: cal)
        let without = mergeAppleItems([], snapshot: AppleSnapshot(events: [], reminders: [copy]),
                                      in: range, today: today, calendar: cal)
        let with = mergeAppleItems([], snapshot: AppleSnapshot(events: [], reminders: [copy, series]),
                                   in: range, today: today, calendar: cal)
        #expect(with == without)
        #expect(with.map(\.title) == ["Renew insurance"])
        #expect(with.first?.isCompleted == true)
    }

    @Test func itStillLetsAnEarlierBlockReadDone() {
        func history(_ reminders: [AppleReminder]) -> DayHistory {
            DayHistory.make(day: at(2026, 11, 2), events: [], reminders: [], plans: [], today: today,
                            apple: AppleSnapshot(events: [], reminders: reminders), sidecarPlans: [block], calendar: cal)
        }
        #expect(history([copy, series]).done.map(\.title) == ["Renew insurance"])
        // Without the series in the snapshot the block has nothing to match and is ignored.
        #expect(!history([copy]).stats.hasPlan)
    }
}
