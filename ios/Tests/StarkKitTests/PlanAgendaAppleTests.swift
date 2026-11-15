import Testing
import Foundation
@testable import StarkKit

/// `applyPlans` with Apple reminders (ids `apple-<identifier>`, from `ItemRouter.plans(on:)`).
struct PlanAgendaAppleTests {
    let cal = Calendar(identifier: .gregorian)
    func at(_ m: Int, _ d: Int, _ h: Int = 0, year: Int = 2026) -> Date {
        cal.date(from: DateComponents(year: year, month: m, day: d, hour: h))!
    }
    /// "Now" is Monday Nov 2 2026, 10:00.
    var today: Date { at(11, 2, 10) }
    let list = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: nil, isReminderList: true)

    func apple(_ id: String, due: Date?, done: Bool = false) -> AppleReminder {
        AppleReminder(id: id, title: "Apple \(id)", notes: nil, due: due, dueHasTime: false, isCompleted: done,
                      completedAt: nil, priority: nil, calendar: list)
    }

    @Test func appleRowPlannedOnAnotherDayKeepsItsRowAndItsSource() {
        let snapshot = AppleSnapshot(events: [], reminders: [apple("r1", due: at(11, 2))])
        let items = mergeAppleItems([], snapshot: snapshot, in: at(11, 1)...at(11, 30, 23), today: today, calendar: cal)
        let plan = PlanBlock(id: "p1", reminderID: "apple-r1", occurrence: at(11, 2), start: at(11, 3, 14), minutes: 30)
        let out = applyPlans(items, plans: [plan], today: today, calendar: cal)
        #expect(out.map(\.displayDate) == [at(11, 2), at(11, 3, 14)])
        #expect(out[1].plan == plan)
        #expect(out[1].appleSource?.calendarID == "L1")
    }

    @Test func appleReminderOutsideTheWindowIsSynthesizedOnItsPlannedDay() {
        let snapshot = AppleSnapshot(events: [], reminders: [apple("far", due: at(6, 1, year: 2027))])
        let plan = PlanBlock(id: "p1", reminderID: "apple-far", occurrence: at(6, 1, year: 2027),
                             start: at(11, 3, 9), minutes: 60)
        let out = applyPlans([], plans: [plan], today: today, apple: snapshot, calendar: cal)
        #expect(out.count == 1)
        #expect(out.first?.plan == plan)
        #expect(out.first?.displayDate == at(11, 3, 9))
        #expect(out.first?.occurrence == at(6, 1, year: 2027))
        #expect(out.first?.isOverdue == false)
        #expect(out.first?.appleSource?.isReminder == true)
        guard case .reminder(let r)? = out.first?.kind else { Issue.record("not a reminder"); return }
        #expect(r.id == "apple-far")
    }

    /// Task 9b fix round 1 (controller decision): a PLANNED undated reminder now appears on its
    /// planned day, so only the completed one stays out (was "completed or undated").
    @Test func completedAppleRemindersAreNeverSynthesizedButAPlannedUndatedOneIs() {
        let snapshot = AppleSnapshot(events: [], reminders: [apple("done", due: at(6, 1, year: 2027), done: true),
                                                             apple("undated", due: nil)])
        let plans = [
            PlanBlock(id: "p1", reminderID: "apple-done", occurrence: at(6, 1, year: 2027), start: at(11, 3, 9), minutes: 30),
            PlanBlock(id: "p2", reminderID: "apple-undated", occurrence: .distantFuture, start: at(11, 3, 11), minutes: 30),
        ]
        let out = applyPlans([], plans: plans, today: today, apple: snapshot, calendar: cal)
        #expect(out.map(\.id).count == 1)
        #expect(out.first?.plan?.id == "p2")
        #expect(out.first?.displayDate == at(11, 3, 11))
    }
}
