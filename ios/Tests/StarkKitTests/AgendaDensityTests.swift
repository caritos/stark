// ios/Tests/StarkKitTests/AgendaDensityTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("AgendaDensity")
struct AgendaDensityTests {
    private let cal = Calendar(identifier: .gregorian)

    /// Fixed "now": Sunday 2026-09-20, 10:00 local. Never `Date()`, so tests are stable.
    private var today: Date { dt("2026-09-20", hour: 10, minute: 0) }

    private let september2026 = YearMonth(year: 2026, month0: 8)

    private func dt(_ iso: String, hour: Int, minute: Int, second: Int = 0, calendar: Calendar? = nil) -> Date {
        let c = DateMath.components(iso)
        return (calendar ?? cal).date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: hour, minute: minute, second: second))!
    }

    private func density(
        events: [Event] = [],
        reminders: [Reminder] = [],
        month: YearMonth? = nil,
        calendar: Calendar? = nil
    ) -> [Int: DayDensity] {
        dayDensity(
            events: events,
            reminders: reminders,
            month: month ?? september2026,
            today: today,
            calendar: calendar ?? cal
        )
    }

    private func event(_ id: String, _ iso: String, hour: Int = 10, recurrence: RecurrenceRule? = nil, exceptions: [Date] = []) -> Event {
        Event(id: id, title: id, start: dt(iso, hour: hour, minute: 0), recurrence: recurrence, exceptionDates: exceptions)
    }

    private func reminder(_ id: String, _ iso: String, hour: Int = 10, completed: Bool = false, recurrence: RecurrenceRule? = nil) -> Reminder {
        Reminder(id: id, title: id, dueDate: dt(iso, hour: hour, minute: 0), isCompleted: completed, recurrence: recurrence)
    }

    // MARK: - Basic counting

    @Test("an empty month yields no entries")
    func emptyMonth() {
        #expect(density().isEmpty)
        // Items that live in other months do not leak in.
        let elsewhere = density(events: [event("e", "2026-10-05")], reminders: [reminder("r", "2026-08-30", completed: true)])
        #expect(elsewhere.isEmpty)
    }

    @Test("an event is counted on its own day, and only that day has an entry")
    func eventOnItsDay() {
        let result = density(events: [event("e", "2026-09-25")])
        #expect(result == [25: DayDensity(tasks: 0, events: 1)])
    }

    @Test("incomplete and completed reminders count as tasks on their due date")
    func remindersOnDueDate() {
        let result = density(reminders: [
            reminder("incomplete", "2026-09-25"),
            reminder("completed-future", "2026-09-25", completed: true),
            reminder("completed-past", "2026-09-10", completed: true),
        ])
        #expect(result == [
            10: DayDensity(tasks: 1, events: 0),
            25: DayDensity(tasks: 2, events: 0),
        ])
    }

    @Test("tasks and events on the same day are counted separately")
    func tasksAndEventsSameDay() {
        let result = density(
            events: [event("e1", "2026-09-22"), event("e2", "2026-09-22", hour: 15)],
            reminders: [reminder("r1", "2026-09-22")]
        )
        #expect(result == [22: DayDensity(tasks: 1, events: 2)])
    }

    @Test("counts are not capped: the view decides how many markers to draw")
    func countsExceedThree() {
        let events = (0..<5).map { event("e\($0)", "2026-09-23", hour: 8 + $0) }
        let reminders = (0..<4).map { reminder("r\($0)", "2026-09-24", hour: 8 + $0) }
        let result = density(events: events, reminders: reminders)
        #expect(result[23] == DayDensity(tasks: 0, events: 5))
        #expect(result[24] == DayDensity(tasks: 4, events: 0))
    }

    @Test("a reminder without a due date has no day to count on")
    func undatedReminder() {
        #expect(density(reminders: [Reminder(title: "Someday")]).isEmpty)
    }

    // MARK: - Overdue

    @Test("an overdue reminder counts on today's cell, not on its missed date")
    func overdueCountsOnToday() {
        let result = density(reminders: [reminder("r", "2026-09-12")])
        #expect(result == [20: DayDensity(tasks: 1, events: 0)])
    }

    @Test("an overdue reminder from the previous month still counts on today (inside the lookback)")
    func overdueFromPreviousMonthCountsOnToday() {
        let result = density(reminders: [reminder("r", "2026-08-25")])
        #expect(result == [20: DayDensity(tasks: 1, events: 0)])
    }

    @Test("an overdue reminder counts on no other month: today is not in it")
    func overdueAbsentFromOtherMonths() {
        let missed = reminder("r", "2026-09-12")
        #expect(density(reminders: [missed], month: YearMonth(year: 2026, month0: 9)).isEmpty)
        #expect(density(reminders: [missed], month: YearMonth(year: 2026, month0: 7)).isEmpty)
    }

    @Test("a reminder due today (later or earlier in the day) is not overdue and counts once on today")
    func dueTodayCountsOnce() {
        let result = density(reminders: [reminder("later", "2026-09-20", hour: 15), reminder("earlier", "2026-09-20", hour: 8)])
        #expect(result == [20: DayDensity(tasks: 2, events: 0)])
    }

    @Test("a weekly reminder keeps only its latest miss (on today) plus its upcoming occurrences")
    func weeklyReminderOverdue() {
        // Mondays from 2026-08-03: misses through 2026-09-14, then upcoming 09-21 and 09-28.
        let weekly = reminder("w", "2026-08-03", recurrence: RecurrenceRule(frequency: .weekly))
        let result = density(reminders: [weekly])
        #expect(result == [
            20: DayDensity(tasks: 1, events: 0),
            21: DayDensity(tasks: 1, events: 0),
            28: DayDensity(tasks: 1, events: 0),
        ])
    }

    // MARK: - Recurrence

    @Test("a weekly event counts on every matching day of the month")
    func weeklyEvent() {
        // 2026-09-07 is a Monday.
        let weekly = event("w", "2026-09-07", recurrence: RecurrenceRule(frequency: .weekly))
        let result = density(events: [weekly])
        #expect(Set(result.keys) == [7, 14, 21, 28])
        #expect(result.values.allSatisfy { $0 == DayDensity(tasks: 0, events: 1) })
    }

    @Test("a recurring event's exception date is not counted")
    func weeklyEventException() {
        let weekly = event("w", "2026-09-07", recurrence: RecurrenceRule(frequency: .weekly), exceptions: [dt("2026-09-21", hour: 10, minute: 0)])
        let result = density(events: [weekly])
        #expect(Set(result.keys) == [7, 14, 28])
    }

    @Test("a recurring event that started years ago still lands on the right days of this month")
    func longRunningRecurringEvent() {
        // 2020-01-06 is a Monday, so it recurs on September 2026's Mondays.
        let weekly = event("w", "2020-01-06", recurrence: RecurrenceRule(frequency: .weekly))
        #expect(Set(density(events: [weekly]).keys) == [7, 14, 21, 28])
    }

    @Test("a monthly event on the 31st clamps to the last day of shorter months")
    func monthlyClamp() {
        let monthly = event("m", "2026-01-31", recurrence: RecurrenceRule(frequency: .monthly))
        #expect(Set(density(events: [monthly], month: YearMonth(year: 2027, month0: 1)).keys) == [28])
        #expect(Set(density(events: [monthly], month: YearMonth(year: 2028, month0: 1)).keys) == [29])
        #expect(Set(density(events: [monthly], month: YearMonth(year: 2026, month0: 9)).keys) == [31])
    }

    // MARK: - Any month, calendar edges

    @Test("a month outside the agenda window works, both far in the future and far in the past")
    func monthsOutsideAgendaWindow() {
        let future = YearMonth(year: 2030, month0: 2)
        let past = YearMonth(year: 2019, month0: 0)
        #expect(!AgendaWindow.range(around: today).contains(dt("2030-03-15", hour: 10, minute: 0)))

        let futureResult = density(
            events: [event("e", "2030-03-15")],
            reminders: [reminder("r", "2030-03-16"), reminder("done", "2030-03-01", completed: true)],
            month: future
        )
        #expect(futureResult == [
            1: DayDensity(tasks: 1, events: 0),
            15: DayDensity(tasks: 0, events: 1),
            16: DayDensity(tasks: 1, events: 0),
        ])

        // Weekly event anchored 2026-09-07 (Monday) recurs on every Monday of March 2030.
        // (Mondays are 2030-03-04, 11, 18 and 25: 2030-03-01 is a Friday.)
        let mondays: Set<Int> = [4, 11, 18, 25]
        let weekly = event("w", "2026-09-07", recurrence: RecurrenceRule(frequency: .weekly))
        #expect(Set(density(events: [weekly], month: future).keys) == mondays)

        let pastResult = density(events: [event("e", "2019-01-31", hour: 23)], month: past)
        #expect(pastResult == [31: DayDensity(tasks: 0, events: 1)])
    }

    @Test("an incomplete reminder in a past month has been pinned to today, so it is not on its old day")
    func incompleteReminderInPastMonth() {
        let old = reminder("old", "2026-02-10")
        #expect(density(reminders: [old], month: YearMonth(year: 2026, month0: 1)).isEmpty)
    }

    @Test("leap-year February has 29 days, a plain February 28")
    func leapYearFebruary() {
        let leap = YearMonth(year: 2028, month0: 1)
        let leapEvents = (1...29).map { event("e\($0)", "2028-02-\(String(format: "%02d", $0))") }
        let leapResult = density(events: leapEvents, month: leap)
        #expect(Set(leapResult.keys) == Set(1...29))
        #expect(leapResult.values.allSatisfy { $0.events == 1 })

        let plain = YearMonth(year: 2027, month0: 1)
        // March 1st must not leak into February.
        let plainEvents = (1...28).map { event("e\($0)", "2027-02-\(String(format: "%02d", $0))") } + [event("mar1", "2027-03-01", hour: 0)]
        let plainResult = density(events: plainEvents, month: plain)
        #expect(Set(plainResult.keys) == Set(1...28))
    }

    @Test("a 31-day month includes the 31st and a 30-day month does not spill into the next")
    func monthLengths() {
        let october = YearMonth(year: 2026, month0: 9)
        #expect(density(events: [event("e", "2026-10-31", hour: 23)], month: october) == [31: DayDensity(tasks: 0, events: 1)])
        let november = YearMonth(year: 2026, month0: 10)
        #expect(density(events: [event("e", "2026-10-31", hour: 23), event("f", "2026-12-01", hour: 0)], month: november).isEmpty)
    }

    @Test("events at the very start of day 1 and the very end of the last day are counted; neighbours are not")
    func firstAndLastDayEdges() {
        let events = [
            event("first-morning", "2026-09-01", hour: 8),
            event("last-late", "2026-09-30", hour: 23),
            Event(id: "midnight", title: "midnight", start: dt("2026-09-01", hour: 0, minute: 0)),
            Event(id: "last-second", title: "last second", start: dt("2026-09-30", hour: 23, minute: 59, second: 59)),
            Event(id: "prev-last-second", title: "before", start: dt("2026-08-31", hour: 23, minute: 59, second: 59)),
            Event(id: "next-midnight", title: "after", start: dt("2026-10-01", hour: 0, minute: 0)),
        ]
        let result = density(events: events)
        #expect(result == [
            1: DayDensity(tasks: 0, events: 2),
            30: DayDensity(tasks: 0, events: 2),
        ])
        // 23:30 on the last day, as in the migrated data's late events.
        let lateReminder = density(reminders: [reminder("late", "2026-09-30", hour: 23, completed: true)])
        #expect(lateReminder == [30: DayDensity(tasks: 1, events: 0)])
    }

    // MARK: - DST

    private var newYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    /// One event at `hour:minute` on every day of the month, built with the New York calendar.
    private func dailyEvents(year: Int, month: Int, days: Int, hour: Int, minute: Int) -> [Event] {
        (1...days).map { day in
            let start = newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
            return Event(id: "e-\(hour)-\(minute)-\(day)", title: "e", start: start)
        }
    }

    @Test("March 2026 (spring-forward on the 8th) keys every day correctly, including the 23-hour day")
    func springForwardMonth() {
        let march = YearMonth(year: 2026, month0: 2)
        let late = density(events: dailyEvents(year: 2026, month: 3, days: 31, hour: 23, minute: 30), month: march, calendar: newYork)
        #expect(Set(late.keys) == Set(1...31))
        #expect(late.values.allSatisfy { $0 == DayDensity(tasks: 0, events: 1) })

        let early = density(events: dailyEvents(year: 2026, month: 3, days: 31, hour: 0, minute: 30), month: march, calendar: newYork)
        #expect(Set(early.keys) == Set(1...31))
        #expect(early.values.allSatisfy { $0 == DayDensity(tasks: 0, events: 1) })

        // Both together: two per day, nothing on the wrong day.
        let both = density(
            events: dailyEvents(year: 2026, month: 3, days: 31, hour: 23, minute: 30) + dailyEvents(year: 2026, month: 3, days: 31, hour: 0, minute: 30),
            month: march,
            calendar: newYork
        )
        #expect(both.values.allSatisfy { $0 == DayDensity(tasks: 0, events: 2) })
    }

    @Test("November 2026 (fall-back on the 1st) keys every day correctly, including the 25-hour day")
    func fallBackMonth() {
        let november = YearMonth(year: 2026, month0: 10)
        let late = density(events: dailyEvents(year: 2026, month: 11, days: 30, hour: 23, minute: 30), month: november, calendar: newYork)
        #expect(Set(late.keys) == Set(1...30))
        #expect(late.values.allSatisfy { $0 == DayDensity(tasks: 0, events: 1) })

        let early = density(events: dailyEvents(year: 2026, month: 11, days: 30, hour: 0, minute: 30), month: november, calendar: newYork)
        #expect(Set(early.keys) == Set(1...30))

        // Neighbouring months' edge events must not leak in around the transition.
        let neighbours = [
            Event(id: "oct", title: "oct", start: newYork.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 30))!),
            Event(id: "dec", title: "dec", start: newYork.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 0, minute: 30))!),
        ]
        #expect(density(events: neighbours, month: november, calendar: newYork).isEmpty)
    }

    // MARK: - Accessibility label

    @Test("a day cell's spoken label is the day, 'today' when it is, then its task and event counts")
    func accessibilityLabels() {
        #expect(DayDensity(tasks: 3, events: 1).accessibilityLabel(day: 20, isToday: true) == "20, today, 3 tasks, 1 event")
        #expect(DayDensity(tasks: 1, events: 2).accessibilityLabel(day: 7, isToday: false) == "7, 1 task, 2 events")
        #expect(DayDensity(tasks: 0, events: 5).accessibilityLabel(day: 31, isToday: false) == "31, 5 events")
        #expect(DayDensity(tasks: 4, events: 0).accessibilityLabel(day: 2, isToday: false) == "2, 4 tasks")
        // Nothing on the day: no counts, and no "0 tasks" noise.
        #expect(DayDensity.none.accessibilityLabel(day: 9, isToday: false) == "9")
        #expect(DayDensity.none.accessibilityLabel(day: 20, isToday: true) == "20, today")
    }

    // MARK: - Performance

    /// The migrated data: ~3,300 events (371 recurring) and ~5,000 reminders. Deterministic
    /// (no randomness) so a failure is reproducible.
    private func migratedDataset() -> (events: [Event], reminders: [Reminder]) {
        let rules: [RecurrenceRule.Frequency] = [.weekly, .monthly, .yearly]
        var events: [Event] = []
        for index in 0..<3_300 {
            // Spread anchors over 2019-2026, days 1...28 so every month has every day.
            let year = 2019 + index % 8
            let month = 1 + index % 12
            let day = 1 + index % 28
            let iso = String(format: "%04d-%02d-%02d", year, month, day)
            let recurrence: RecurrenceRule? = index < 371 ? RecurrenceRule(frequency: rules[index % 3]) : nil
            events.append(Event(id: "e\(index)", title: "Event \(index)", start: dt(iso, hour: index % 24, minute: 0), recurrence: recurrence))
        }

        var reminders: [Reminder] = []
        for index in 0..<5_000 {
            let year = 2024 + index % 4
            let month = 1 + index % 12
            let day = 1 + index % 28
            let iso = String(format: "%04d-%02d-%02d", year, month, day)
            // ~4% recurring (weekly/monthly, incomplete), the rest one-offs, 60% completed.
            let recurrence: RecurrenceRule? = index % 25 == 0 ? RecurrenceRule(frequency: rules[index % 2]) : nil
            let completed = recurrence == nil && index % 5 < 3
            reminders.append(Reminder(id: "r\(index)", title: "Reminder \(index)", dueDate: dt(iso, hour: index % 24, minute: 30), isCompleted: completed, recurrence: recurrence))
        }
        return (events, reminders)
    }

    @Test("a month over the migrated dataset (3,300 events incl. 371 recurring, 5,000 reminders) computes well under 2s")
    func largeDatasetTiming() {
        let (events, reminders) = migratedDataset()
        #expect(events.filter { $0.recurrence != nil }.count == 371)

        let clock = ContinuousClock()
        // Today's month (overdue lookback in play), a nearby future month, a month far in the
        // future (recurring reminders walk the longest), and a month in the past.
        let months = [
            YearMonth(year: 2026, month0: 8),
            YearMonth(year: 2026, month0: 9),
            YearMonth(year: 2028, month0: 5),
            YearMonth(year: 2025, month0: 2),
        ]
        for month in months {
            var result: [Int: DayDensity] = [:]
            let elapsed = clock.measure {
                result = dayDensity(events: events, reminders: reminders, month: month, today: today, calendar: cal)
            }
            #expect(elapsed < .seconds(2), "\(month) took \(elapsed)")
            #expect(!result.isEmpty)
            #expect(result.keys.allSatisfy { (1...31).contains($0) })
        }
    }
}
