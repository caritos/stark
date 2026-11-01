import Testing
import Foundation
@testable import StarkKit

@Suite("PlanDensity")
struct PlanDensityTests {
    private let cal = Calendar(identifier: .gregorian)
    /// Sunday 2026-09-20, 10:00 local.
    private var today: Date { dt("2026-09-20", hour: 10) }
    private let month = YearMonth(year: 2026, month0: 8)

    private func dt(_ iso: String, hour: Int) -> Date {
        let c = DateMath.components(iso)
        return cal.date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: hour))!
    }

    private var overdue: Reminder { Reminder(id: "r", title: "Call bank", dueDate: dt("2026-09-18", hour: 9)) }
    private func plan(on iso: String) -> PlanBlock {
        PlanBlock(id: "p", reminderID: "r", occurrence: dt("2026-09-18", hour: 9), start: dt(iso, hour: 14), minutes: 30)
    }

    @Test("an overdue task planned inside the grid counts on today and on the planned day")
    func gridCountsPlannedDay() {
        let result = gridDensity(events: [], reminders: [overdue], month: month, today: today,
                                 plans: [plan(on: "2026-09-22")])
        #expect(result["2026-09-20"] == DayDensity(tasks: 1, events: 0))
        #expect(result["2026-09-22"] == DayDensity(tasks: 1, events: 0))
        #expect(result.count == 2)
    }

    @Test("the year density counts the planned day too")
    func yearCountsPlannedDay() {
        let result = yearDensity(events: [], reminders: [overdue], year: 2026, today: today,
                                 plans: [plan(on: "2026-10-05")])
        #expect(result["2026-09-20"] == DayDensity(tasks: 1, events: 0))
        #expect(result["2026-10-05"] == DayDensity(tasks: 1, events: 0))
        #expect(result.count == 2)
    }

    @Test("a lapsed plan adds nothing")
    func lapsedPlanAddsNothing() {
        let plain = gridDensity(events: [], reminders: [overdue], month: month, today: today)
        let result = gridDensity(events: [], reminders: [overdue], month: month, today: today,
                                 plans: [plan(on: "2026-09-19")])
        #expect(result == plain)
        #expect(result["2026-09-19"] == nil)
    }

    @Test("empty plans equal the old result on a mixed fixture")
    func emptyPlansUnchanged() {
        let daily = RecurrenceRule(frequency: .daily)
        let reminders = [
            overdue,
            Reminder(id: "d", title: "Daily", dueDate: dt("2026-09-10", hour: 7), recurrence: daily),
            Reminder(id: "f", title: "Future", dueDate: dt("2026-09-25", hour: 12)),
        ]
        let events = [Event(id: "e", title: "Standup", start: dt("2026-09-14", hour: 9), recurrence: daily)]
        #expect(gridDensity(events: events, reminders: reminders, month: month, today: today, plans: [])
                == gridDensity(events: events, reminders: reminders, month: month, today: today))
        #expect(yearDensity(events: events, reminders: reminders, year: 2026, today: today, plans: [])
                == yearDensity(events: events, reminders: reminders, year: 2026, today: today))
    }
}
