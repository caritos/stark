// ios/Tests/StarkKitTests/YearDensityTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("yearDensity")
struct YearDensityTests {
    private let cal = Calendar(identifier: .gregorian)
    private var today: Date { DateMath.date(from: "2026-09-20") }

    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }

    @Test("the year range runs from the start of Jan 1 to the last second of Dec 31")
    func range() {
        let range = YearGrid.range(year: 2026)

        #expect(range.lowerBound == cal.startOfDay(for: d("2026-01-01")))
        #expect(range.upperBound == cal.startOfDay(for: d("2027-01-01")).addingTimeInterval(-1))
        #expect(range.contains(d("2026-12-31")))
        #expect(!range.contains(d("2025-12-31")))
        #expect(!range.contains(d("2027-01-01")))
    }

    @Test("counts land on their days across the year and nothing outside the year is counted")
    func countsAcrossTheYear() {
        let events = [
            Event(id: "e0", title: "Last year", start: d("2025-12-31")),
            Event(id: "e1", title: "New Year", start: d("2026-01-01")),
            Event(id: "e2", title: "June", start: d("2026-06-15")),
            Event(id: "e3", title: "New Year's Eve", start: d("2026-12-31")),
            Event(id: "e4", title: "Next year", start: d("2027-01-01")),
        ]
        let reminders = [Reminder(id: "r1", title: "October", dueDate: d("2026-10-05"))]

        let result = yearDensity(events: events, reminders: reminders, year: 2026, today: today)

        #expect(result["2026-01-01"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-06-15"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-10-05"] == DayDensity(tasks: 1, events: 0))
        #expect(result["2026-12-31"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2025-12-31"] == nil)
        #expect(result["2027-01-01"] == nil)
        #expect(result.count == 4)
    }

    @Test("a weekly event is counted on each of its days")
    func recurringEvent() {
        let weekly = Event(id: "w", title: "Weekly", start: d("2026-01-05"), recurrence: RecurrenceRule(frequency: .weekly))

        let result = yearDensity(events: [weekly], reminders: [], year: 2026, today: today)

        #expect(result["2026-01-05"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-01-12"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-12-28"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-01-06"] == nil)
        #expect(result.count == 52)
    }

    @Test("an overdue reminder counts on today's day when today is in the year, and nowhere otherwise")
    func overdue() {
        let reminders = [Reminder(id: "r1", title: "Missed", dueDate: d("2026-09-01"))]

        let inYear = yearDensity(events: [], reminders: reminders, year: 2026, today: today)
        #expect(inYear["2026-09-20"] == DayDensity(tasks: 1, events: 0))
        #expect(inYear["2026-09-01"] == nil)

        let otherYear = yearDensity(events: [], reminders: reminders, year: 2027, today: today)
        #expect(otherYear.isEmpty)
    }

    @Test("it agrees with gridDensity for the days both cover")
    func agreesWithGridDensity() {
        let events = [
            Event(id: "e1", title: "A", start: d("2026-09-03")),
            Event(id: "e2", title: "B", start: d("2026-09-03")),
            Event(id: "w", title: "Weekly", start: d("2026-09-02"), recurrence: RecurrenceRule(frequency: .weekly)),
        ]
        let reminders = [
            Reminder(id: "r1", title: "Later", dueDate: d("2026-09-28")),
            Reminder(id: "r2", title: "Missed", dueDate: d("2026-09-05")),
        ]

        let year = yearDensity(events: events, reminders: reminders, year: 2026, today: today)
        let grid = gridDensity(events: events, reminders: reminders, month: YearMonth(year: 2026, month0: 8), today: today)

        #expect(!grid.isEmpty)
        for (iso, density) in grid {
            #expect(year[iso] == density)
        }
    }

    @Test("level buckets the total count: 0, 1, 2-3, 4 or more")
    func level() {
        #expect(DayDensity.none.level == 0)
        #expect(DayDensity(tasks: 1, events: 0).level == 1)
        #expect(DayDensity(tasks: 0, events: 1).level == 1)
        #expect(DayDensity(tasks: 1, events: 1).level == 2)
        #expect(DayDensity(tasks: 2, events: 1).level == 2)
        #expect(DayDensity(tasks: 2, events: 2).level == 3)
        #expect(DayDensity(tasks: 5, events: 0).level == 3)
    }
}
