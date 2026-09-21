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

    // MARK: - Equivalence with the slow, obviously-correct count

    /// The count computed the slow way: `buildAgendaItems` over exactly `range` with the real
    /// `today` and the default lookback, keep only rows displayed inside `range`, count per ISO day.
    /// This is what `gridDensity`/`yearDensity` must equal whatever shortcuts they take.
    private func slowCounts(
        events: [Event],
        reminders: [Reminder],
        range: ClosedRange<Date>,
        today: Date
    ) -> [String: DayDensity] {
        var result: [String: DayDensity] = [:]
        for item in buildAgendaItems(events: events, reminders: reminders, in: range, today: today) {
            guard range.contains(item.displayDate) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: item.displayDate)
            let iso = DateMath.isoDate(year: c.year!, month0: c.month! - 1, day: c.day!)
            switch item.kind {
            case .event: result[iso, default: .none].events += 1
            case .reminder: result[iso, default: .none].tasks += 1
            }
        }
        return result
    }

    private var mixedEvents: [Event] {
        [
            Event(id: "weekly-event", title: "Weekly", start: d("2026-08-03"), recurrence: RecurrenceRule(frequency: .weekly)),
            Event(id: "one-off-2028", title: "One-off", start: d("2028-03-14")),
            Event(id: "one-off-2025", title: "Past one-off", start: d("2025-06-10")),
        ]
    }

    private var mixedReminders: [Reminder] {
        [
            // Started before today and still running: its missed daily occurrences are dropped.
            Reminder(id: "daily", title: "Daily", dueDate: d("2026-08-01"), recurrence: RecurrenceRule(frequency: .daily)),
            // Weekly and monthly: each keeps only its latest miss, pinned to today.
            Reminder(id: "weekly", title: "Weekly", dueDate: d("2026-08-03"), recurrence: RecurrenceRule(frequency: .weekly), exceptionDates: [d("2026-08-10")]),
            Reminder(id: "monthly", title: "Monthly", dueDate: d("2026-01-31"), recurrence: RecurrenceRule(frequency: .monthly)),
            // One-offs: two in the future, one missed (overdue) and one long missed.
            Reminder(id: "future-2028", title: "Future", dueDate: d("2028-03-10")),
            Reminder(id: "future-2026", title: "Soon", dueDate: d("2026-11-02")),
            Reminder(id: "missed", title: "Missed", dueDate: d("2026-09-01")),
            Reminder(id: "long-missed", title: "Long missed", dueDate: d("2025-03-03")),
            // Completed reminders appear on their due date and are never overdue.
            Reminder(id: "done-2028", title: "Done later", dueDate: d("2028-05-05"), isCompleted: true),
            Reminder(id: "done-2025", title: "Done earlier", dueDate: d("2025-06-01"), isCompleted: true),
            // A recurring reminder that only starts in the target year.
            Reminder(id: "starts-2028", title: "Starts later", dueDate: d("2028-02-01"), recurrence: RecurrenceRule(frequency: .weekly)),
        ]
    }

    @Test("yearDensity equals the slow count for a future year, the current year, a past year and the boundary days",
          arguments: [
            (2028, "2026-09-20"),  // a future year
            (2027, "2026-09-20"),  // the next year
            (2026, "2026-09-20"),  // today inside the year
            (2025, "2026-09-20"),  // a past year
            (2028, "2027-12-31"),  // today is the day before the year starts
            (2028, "2028-01-01"),  // today is the first day of the year
            (2028, "2028-12-31"),  // today is the last day of the year
            (2028, "2029-01-01"),  // the year is wholly in the past by one day
          ])
    func yearDensityMatchesSlowCount(year: Int, todayISO: String) {
        let now = d(todayISO)
        let expected = slowCounts(events: mixedEvents, reminders: mixedReminders, range: YearGrid.range(year: year), today: now)

        let actual = yearDensity(events: mixedEvents, reminders: mixedReminders, year: year, today: now, calendar: cal)

        #expect(!expected.isEmpty, "the dataset should put something in \(year)")
        #expect(actual == expected, "year \(year), today \(todayISO)")
    }

    @Test("gridDensity equals the slow count for a future month grid, the current one and a past one",
          arguments: [
            (YearMonth(year: 2028, month0: 2), "2026-09-20"),  // a future month (neighbours in Feb and Apr)
            (YearMonth(year: 2026, month0: 10), "2026-09-20"), // next month, whose grid still shows Sep days
            (YearMonth(year: 2026, month0: 8), "2026-09-20"),  // today's month
            (YearMonth(year: 2025, month0: 5), "2026-09-20"),  // a past month
            (YearMonth(year: 2028, month0: 2), "2028-02-28"),  // today is inside the grid's leading days
          ])
    func gridDensityMatchesSlowCount(month: YearMonth, todayISO: String) {
        let now = d(todayISO)
        let expected = slowCounts(events: mixedEvents, reminders: mixedReminders, range: MonthGrid.range(for: month, calendar: cal), today: now)

        let actual = gridDensity(events: mixedEvents, reminders: mixedReminders, month: month, today: now, calendar: cal)

        #expect(actual == expected, "month \(month), today \(todayISO)")
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
