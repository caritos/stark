import Testing
import Foundation
@testable import StarkKit

/// `agendaWithApple`: Apple rows are merged BEFORE plans are applied, so a planned Apple
/// reminder is never listed twice.
struct AgendaWithAppleTests {
    let cal = Calendar(identifier: .gregorian)
    func at(_ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }
    var today: Date { at(11, 2, 10) }
    var range: ClosedRange<Date> { at(11, 1)...at(11, 30, 23) }
    let list = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: nil, isReminderList: true)
    var snapshot: AppleSnapshot {
        AppleSnapshot(events: [], reminders: [
            AppleReminder(id: "r1", title: "Buy stamps", notes: nil, due: at(11, 2), dueHasTime: false,
                          isCompleted: false, completedAt: nil, priority: nil, calendar: list),
        ])
    }

    @Test func appleReminderPlannedOnAnotherDayIsListedOncePerDay() {
        let plan = PlanBlock(id: "p1", reminderID: "apple-r1", occurrence: at(11, 2), start: at(11, 3, 14), minutes: 30)
        let rows = agendaWithApple(local: [], snapshot: snapshot, plans: [plan], range: range, today: today, calendar: cal)
        #expect(rows.map(\.displayDate) == [at(11, 2), at(11, 3, 14)])
        #expect(rows.map(\.plan) == [nil, plan])
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.allSatisfy { $0.appleSource != nil })
    }

    @Test func appleReminderPlannedOnItsOwnDayReplacesItsRow() {
        let plan = PlanBlock(id: "p1", reminderID: "apple-r1", occurrence: at(11, 2), start: at(11, 2, 15), minutes: 30)
        let rows = agendaWithApple(local: [], snapshot: snapshot, plans: [plan], range: range, today: today, calendar: cal)
        #expect(rows.count == 1)
        #expect(rows.first?.plan == plan)
    }

    @Test func emptySnapshotIsApplyPlansOnLocalRows() {
        let local = Reminder(id: "l1", title: "Local", dueDate: at(11, 2))
        let items = buildAgendaItems(events: [], reminders: [local], in: range, today: today)
        let plan = PlanBlock(id: "p1", reminderID: "l1", occurrence: at(11, 2), start: at(11, 4, 9), minutes: 30)
        #expect(agendaWithApple(local: items, snapshot: .empty, plans: [plan], range: range, today: today,
                                reminders: [local], calendar: cal)
                == applyPlans(items, plans: [plan], today: today, reminders: [local], calendar: cal))
    }
}
