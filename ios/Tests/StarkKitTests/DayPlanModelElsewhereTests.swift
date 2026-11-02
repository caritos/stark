import Testing
import Foundation
@testable import StarkKit

struct DayPlanModelElsewhereTests {
    let cal = Calendar(identifier: .gregorian)

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    var today: Date { at(2026, 11, 4, 10) }

    func ids(_ items: [AgendaItem]) -> [String] {
        items.compactMap { if case .reminder(let r) = $0.kind { return r.id } else { return nil } }
    }

    func make(day: Date, reminders: [Reminder], elsewhere: [PlanBlock]) -> DayPlanModel {
        DayPlanModel.make(day: day, events: [], reminders: reminders, plans: [], today: today,
                          plannedElsewhere: elsewhere, calendar: cal)
    }

    @Test func plannedOnAnotherDayLeavesTray() {
        let r = Reminder(id: "r", title: "Pay rent", dueDate: at(2026, 11, 5))
        let block = PlanBlock(id: "p", reminderID: "r", occurrence: at(2026, 11, 5), start: at(2026, 11, 6, 9), minutes: 30)
        #expect(ids(make(day: at(2026, 11, 5), reminders: [r], elsewhere: []).tray) == ["r"])
        #expect(ids(make(day: at(2026, 11, 5), reminders: [r], elsewhere: [block]).tray).isEmpty)
    }

    @Test func lapsedElsewhereBlockDoesNotHide() {
        let r = Reminder(id: "r", title: "Pay rent", dueDate: at(2026, 11, 5))
        let block = PlanBlock(id: "p", reminderID: "r", occurrence: at(2026, 11, 5), start: at(2026, 11, 2, 9), minutes: 30)
        #expect(ids(make(day: at(2026, 11, 5), reminders: [r], elsewhere: [block]).tray) == ["r"])
    }

    @Test func recurringOtherOccurrenceNotHidden() {
        let daily = Reminder(id: "s", title: "Stretch", dueDate: at(2026, 11, 4, 8),
                             recurrence: RecurrenceRule(frequency: .daily))
        let other = PlanBlock(id: "p1", reminderID: "s", occurrence: at(2026, 11, 5, 8), start: at(2026, 11, 6, 9), minutes: 30)
        let same = PlanBlock(id: "p2", reminderID: "s", occurrence: at(2026, 11, 4, 8), start: at(2026, 11, 6, 9), minutes: 30)
        #expect(ids(make(day: at(2026, 11, 5), reminders: [daily], elsewhere: [other]).tray) == ["s"])
        #expect(ids(make(day: at(2026, 11, 5), reminders: [daily], elsewhere: [same]).tray).isEmpty)
    }

    @Test func timedTaskPlannedElsewhereLeavesTimeline() {
        let r = Reminder(id: "t", title: "Call", dueDate: at(2026, 11, 5, 14))
        let block = PlanBlock(id: "p", reminderID: "t", occurrence: at(2026, 11, 5, 14), start: at(2026, 11, 6, 9), minutes: 30)
        #expect(ids(make(day: at(2026, 11, 5), reminders: [r], elsewhere: []).timed) == ["t"])
        let model = make(day: at(2026, 11, 5), reminders: [r], elsewhere: [block])
        #expect(model.timed.isEmpty)
        #expect(model.tray.isEmpty)
    }
}
