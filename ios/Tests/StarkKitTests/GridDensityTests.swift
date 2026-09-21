// ios/Tests/StarkKitTests/GridDensityTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("gridDensity")
struct GridDensityTests {
    private let sept = YearMonth(year: 2026, month0: 8)
    private var today: Date { DateMath.date(from: "2026-09-20") }

    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }

    @Test("counts land on neighbouring-month cells too, and nothing beyond the grid is counted")
    func countsNeighbours() {
        let events = [
            Event(id: "e1", title: "Aug 31", start: d("2026-08-31")),
            Event(id: "e2", title: "Sep 15", start: d("2026-09-15")),
            Event(id: "e3", title: "Oct 2", start: d("2026-10-02")),
            Event(id: "e4", title: "Oct 20", start: d("2026-10-20")),
        ]
        let reminders = [
            Reminder(id: "r1", title: "Sep 25", dueDate: d("2026-09-25")),
            Reminder(id: "r2", title: "Oct 5", dueDate: d("2026-10-05")),
        ]

        let result = gridDensity(events: events, reminders: reminders, month: sept, today: today)

        #expect(result["2026-08-31"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-09-15"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-09-25"] == DayDensity(tasks: 1, events: 0))
        #expect(result["2026-10-02"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-10-05"] == DayDensity(tasks: 1, events: 0))
        #expect(result["2026-10-20"] == nil)
        #expect(result.count == 5)
    }

    @Test("an overdue reminder counts on today's cell, not its missed day")
    func overdueCountsOnToday() {
        let reminders = [Reminder(id: "r1", title: "Missed", dueDate: d("2026-09-01"))]

        let result = gridDensity(events: [], reminders: reminders, month: sept, today: today)

        #expect(result["2026-09-20"] == DayDensity(tasks: 1, events: 0))
        #expect(result["2026-09-01"] == nil)
    }

    @Test("an overdue reminder counts on today's cell even when today is a neighbouring-month cell")
    func overdueCountsOnTodayInNeighbourCell() {
        // October 2026's grid runs Sep 27 - Nov 7, so 2026-09-30 is a September cell on it.
        let october = YearMonth(year: 2026, month0: 9)
        let reminders = [Reminder(id: "r1", title: "Missed", dueDate: d("2026-09-01"))]

        let result = gridDensity(events: [], reminders: reminders, month: october, today: d("2026-09-30"))

        #expect(result["2026-09-30"] == DayDensity(tasks: 1, events: 0))
        #expect(result["2026-09-01"] == nil)
    }

    @Test("an overdue reminder is not counted when today is outside the grid range")
    func overdueIgnoredWhenTodayOutside() {
        let reminders = [Reminder(id: "r1", title: "Missed", dueDate: d("2026-09-01"))]

        let result = gridDensity(events: [], reminders: reminders, month: YearMonth(year: 2026, month0: 11), today: today)

        #expect(result.isEmpty)
    }

    @Test("for days inside the month it agrees with dayDensity")
    func agreesWithDayDensity() {
        let events = [
            Event(id: "e1", title: "A", start: d("2026-09-03")),
            Event(id: "e2", title: "B", start: d("2026-09-03")),
            Event(id: "w", title: "Weekly", start: d("2026-09-02"), recurrence: RecurrenceRule(frequency: .weekly)),
        ]
        let reminders = [
            Reminder(id: "r1", title: "Later", dueDate: d("2026-09-28")),
            Reminder(id: "r2", title: "Missed", dueDate: d("2026-09-05")),
        ]

        let month = dayDensity(events: events, reminders: reminders, month: sept, today: today)
        let grid = gridDensity(events: events, reminders: reminders, month: sept, today: today)

        #expect(!month.isEmpty)
        for (day, density) in month {
            #expect(grid[DateMath.isoDate(year: 2026, month0: 8, day: day)] == density)
        }
    }
}
