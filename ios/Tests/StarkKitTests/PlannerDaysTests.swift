import Testing
import Foundation
@testable import StarkKit

struct PlannerDaysTests {
    let cal = Calendar(identifier: .gregorian)

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, calendar: Calendar? = nil) -> Date {
        (calendar ?? cal).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    /// "Now" is Wednesday Nov 4 2026, 10:00.
    var today: Date { at(2026, 11, 4, 10) }

    @Test func editableFromTodayOn() {
        #expect(PlannerDays.isEditable(at(2026, 11, 4, 0), today: today))
        #expect(PlannerDays.isEditable(at(2026, 11, 4, 23, 59), today: today))
        #expect(PlannerDays.isEditable(at(2026, 11, 5), today: today))
        #expect(!PlannerDays.isEditable(at(2026, 11, 3, 23, 59), today: today))
    }

    @Test func stepAcrossDSTEnd() {
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let nov1 = at(2026, 11, 1, calendar: la)
        let nov2 = at(2026, 11, 2, calendar: la)
        #expect(PlannerDays.step(nov1, by: 1, calendar: la) == nov2)
        #expect(PlannerDays.step(nov2, by: -1, calendar: la) == nov1)
    }

    @Test func stepKeepsStartOfDay() {
        #expect(PlannerDays.step(at(2026, 11, 4, 15), by: 0) == at(2026, 11, 4))
    }

    @Test func loadRangeCoversWeekAndLookback() {
        let day = at(2026, 11, 4)
        let r = PlannerDays.loadRange(for: day)
        #expect(r.lowerBound <= AgendaWindow.loadRange(around: at(2026, 11, 1)).lowerBound)
        #expect(r.upperBound >= AgendaWindow.loadRange(around: at(2026, 11, 7)).upperBound)
        let own = AgendaWindow.loadRange(around: day)
        #expect(r.contains(own.lowerBound) && r.contains(own.upperBound))
        let far = at(2027, 12, 15)
        #expect(PlannerDays.loadRange(for: far).contains(far))
    }
}
