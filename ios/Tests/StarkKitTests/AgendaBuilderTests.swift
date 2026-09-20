// ios/Tests/StarkKitTests/AgendaBuilderTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("AgendaBuilder")
struct AgendaBuilderTests {
    private let cal = Calendar(identifier: .gregorian)

    /// Fixed "now": Sunday 2026-09-20, 10:00 local. Never `Date()`, so tests are stable.
    private var today: Date { dt("2026-09-20", hour: 10, minute: 0) }
    private var todayStart: Date { cal.startOfDay(for: today) }
    private var display: ClosedRange<Date> { AgendaWindow.range(around: today) }

    /// Noon on the given ISO day.
    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }

    private func dt(_ iso: String, hour: Int, minute: Int) -> Date {
        let c = DateMath.components(iso)
        return cal.date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: hour, minute: minute))!
    }

    private func build(events: [Event] = [], reminders: [Reminder] = [], lookback: Int = AgendaWindow.overdueLookbackDays) -> [AgendaItem] {
        buildAgendaItems(events: events, reminders: reminders, in: display, today: today, overdueLookbackDays: lookback)
    }

    private func iso(_ date: Date) -> String { DateMath.isoDate(from: date) }

    // MARK: - Normal rows

    @Test("a normal event and reminder inside the range appear at their own date, in order")
    func normalEventAndReminder() {
        let event = Event(id: "e1", title: "Standup", start: d("2026-09-25"))
        let reminder = Reminder(id: "r1", title: "Pay rent", dueDate: d("2026-09-27"))

        let items = build(events: [event], reminders: [reminder])

        #expect(items.count == 2)
        #expect(items[0].kind == .event(event))
        #expect(items[0].occurrence == d("2026-09-25"))
        #expect(items[0].displayDate == d("2026-09-25"))
        #expect(items[0].isOverdue == false)
        #expect(items[0].isCompleted == false)
        #expect(items[0].isRecurring == false)
        #expect(items[0].title == "Standup")
        #expect(items[1].kind == .reminder(reminder))
        #expect(items[1].displayDate == d("2026-09-27"))
        #expect(items[1].title == "Pay rent")
    }

    @Test("id is '<item id>-<occurrence timeIntervalSince1970>' and isRecurring reflects the rule")
    func idSchemeAndRecurringFlag() {
        let reminder = Reminder(id: "r1", title: "Trash", dueDate: d("2026-09-21"), recurrence: RecurrenceRule(frequency: .weekly))

        let items = build(reminders: [reminder])

        let first = items.first!
        #expect(first.id == "r1-\(first.occurrence.timeIntervalSince1970)")
        #expect(items.allSatisfy { $0.isRecurring })
    }

    @Test("an incomplete reminder with no due date never appears")
    func reminderWithoutDueDate() {
        #expect(build(reminders: [Reminder(title: "Someday")]).isEmpty)
    }

    // MARK: - Completed reminders

    @Test("a completed one-off appears at its due date, never overdue, even when that date is in the past")
    func completedOneOffAppearsAtDueDate() {
        let future = Reminder(id: "c1", title: "Done later", dueDate: d("2026-09-22"), isCompleted: true, completedDate: d("2026-09-22"))
        let past = Reminder(id: "c2", title: "Done earlier", dueDate: d("2026-09-10"), isCompleted: true, completedDate: d("2026-09-10"))

        let items = build(reminders: [future, past])

        #expect(items.map(\.title) == ["Done earlier", "Done later"])
        #expect(items.allSatisfy { $0.isCompleted && !$0.isOverdue })
        #expect(items[0].displayDate == d("2026-09-10"))
        #expect(items[1].displayDate == d("2026-09-22"))
    }

    @Test("a completed reminder outside the display range, or without a due date, is not shown")
    func completedOutsideRangeOrWithoutDueDate() {
        // 2026-08-01 is inside the overdue lookback but outside the display range.
        let old = Reminder(title: "Old", dueDate: d("2026-08-01"), isCompleted: true)
        let undated = Reminder(title: "Undated", isCompleted: true)

        #expect(build(reminders: [old, undated]).isEmpty)
    }

    @Test("a completed item sorts after incomplete items on the same day, even when it is earlier in the day")
    func completedSortsLastWithinDay() {
        let completed = Reminder(id: "a", title: "Completed", dueDate: dt("2026-09-22", hour: 8, minute: 0), isCompleted: true)
        let incomplete = Reminder(id: "b", title: "Incomplete", dueDate: dt("2026-09-22", hour: 17, minute: 0))
        let event = Event(id: "c", title: "Event", start: dt("2026-09-22", hour: 12, minute: 0))

        let items = build(events: [event], reminders: [completed, incomplete])

        #expect(items.map(\.title) == ["Event", "Incomplete", "Completed"])
    }

    // MARK: - Overdue pinning

    @Test("an incomplete one-off due yesterday is overdue, pinned to start of today, keeping its real occurrence")
    func overdueYesterday() {
        let due = dt("2026-09-19", hour: 15, minute: 0)
        let reminder = Reminder(id: "r1", title: "Call plumber", dueDate: due)

        let items = build(reminders: [reminder])

        #expect(items.count == 1)
        #expect(items[0].isOverdue)
        #expect(items[0].displayDate == todayStart)
        #expect(items[0].occurrence == due)
        #expect(items[0].id == "r1-\(due.timeIntervalSince1970)")
    }

    @Test("due later today, or earlier today, is not overdue (day granularity)")
    func dueTodayIsNotOverdue() {
        let later = Reminder(id: "later", title: "Later", dueDate: dt("2026-09-20", hour: 15, minute: 0))
        let earlier = Reminder(id: "earlier", title: "Earlier", dueDate: dt("2026-09-20", hour: 8, minute: 0))

        let items = build(reminders: [later, earlier])

        #expect(items.count == 2)
        #expect(items.allSatisfy { !$0.isOverdue })
        #expect(items[0].displayDate == dt("2026-09-20", hour: 8, minute: 0))
        #expect(items[1].displayDate == dt("2026-09-20", hour: 15, minute: 0))
    }

    @Test("overdue reminders older than the display window show up, bounded by the lookback")
    func overdueLookbackBound() {
        // today is 2026-09-20: 60 days back = 2026-07-22, 100 days back = 2026-06-12.
        let sixty = Reminder(id: "sixty", title: "Sixty", dueDate: d("2026-07-22"))
        let hundred = Reminder(id: "hundred", title: "Hundred", dueDate: d("2026-06-12"))

        let items = build(reminders: [sixty, hundred])

        #expect(items.map(\.title) == ["Sixty"])
        #expect(items[0].isOverdue)
        #expect(items[0].occurrence == d("2026-07-22"))

        // The bound is a parameter, not a constant baked into the expansion.
        #expect(build(reminders: [sixty, hundred], lookback: 30).isEmpty)
        #expect(build(reminders: [sixty, hundred], lookback: 120).map(\.title) == ["Hundred", "Sixty"])
    }

    @Test("a weekly reminder with three missed occurrences yields exactly one overdue row: the latest")
    func weeklyOnlyLatestMissedIsOverdue() {
        // Mondays: Aug 31, Sep 7, Sep 14 are missed; Sep 21 onward is upcoming.
        let reminder = Reminder(id: "w", title: "Weekly review", dueDate: d("2026-08-31"), recurrence: RecurrenceRule(frequency: .weekly))

        let items = build(reminders: [reminder])

        let overdue = items.filter(\.isOverdue)
        #expect(overdue.count == 1)
        #expect(overdue[0].occurrence == d("2026-09-14"))
        #expect(overdue[0].displayDate == todayStart)
        #expect(overdue[0].isRecurring)

        let upcoming = items.filter { !$0.isOverdue }
        #expect(upcoming.map { iso($0.occurrence) } == [
            "2026-09-21", "2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19",
            "2026-10-26", "2026-11-02", "2026-11-09", "2026-11-16",
        ])
        #expect(upcoming.allSatisfy { $0.displayDate == $0.occurrence })

        // The earlier missed occurrences are dropped entirely, not shown at their own dates.
        #expect(!items.contains { iso($0.occurrence) == "2026-08-31" || iso($0.occurrence) == "2026-09-07" })
    }

    @Test("a monthly reminder keeps only its most recent missed occurrence as overdue")
    func monthlyOnlyLatestMissedIsOverdue() {
        // Day 25: Jun 25, Jul 25, Aug 25 are missed; Sep 25 and Oct 25 are upcoming
        // (Nov 25 is past the display window).
        let reminder = Reminder(id: "m", title: "Pay card", dueDate: d("2026-06-25"), recurrence: RecurrenceRule(frequency: .monthly))

        let items = build(reminders: [reminder])

        #expect(items.filter(\.isOverdue).map { iso($0.occurrence) } == ["2026-08-25"])
        #expect(items.filter { !$0.isOverdue }.map { iso($0.occurrence) } == ["2026-09-25", "2026-10-25"])
    }

    @Test("a daily recurring reminder never yields an overdue row")
    func dailyNeverOverdue() {
        let reminder = Reminder(id: "d", title: "Vitamins", dueDate: d("2026-09-15"), recurrence: RecurrenceRule(frequency: .daily))

        let items = build(reminders: [reminder])

        #expect(items.allSatisfy { !$0.isOverdue })
        #expect(items.allSatisfy { $0.occurrence >= todayStart })
        #expect(iso(items.first!.occurrence) == "2026-09-20")
        // 2026-09-20 through 2026-11-19 inclusive.
        #expect(items.count == 61)
    }

    @Test("a skipped or completed (exdated) missed occurrence is not overdue")
    func exdatedMissedOccurrenceIsNotOverdue() {
        let anchor = d("2026-08-31")
        let rule = RecurrenceRule(frequency: .weekly)

        // The latest missed occurrence (Sep 14) was skipped, so the next-most-recent one is
        // the overdue row.
        let skippedLatest = Reminder(id: "w", title: "Weekly review", dueDate: anchor, recurrence: rule, exceptionDates: [d("2026-09-14")])
        #expect(build(reminders: [skippedLatest]).filter(\.isOverdue).map { iso($0.occurrence) } == ["2026-09-07"])

        // Every missed occurrence resolved: no overdue row at all.
        let allResolved = Reminder(
            id: "w", title: "Weekly review", dueDate: anchor, recurrence: rule,
            exceptionDates: [d("2026-08-31"), d("2026-09-07"), d("2026-09-14")]
        )
        #expect(build(reminders: [allResolved]).filter(\.isOverdue).isEmpty)
    }

    // MARK: - Events

    @Test("events in the past inside the display window stay at their own date and are never overdue")
    func pastEventsStayPut() {
        let oneOff = Event(id: "e1", title: "Dinner", start: d("2026-09-10"))
        let weekly = Event(id: "e2", title: "Class", start: d("2026-09-08"), recurrence: RecurrenceRule(frequency: .weekly))

        let items = build(events: [oneOff, weekly])

        #expect(items.allSatisfy { !$0.isOverdue && $0.displayDate == $0.occurrence })
        #expect(items.contains { $0.title == "Dinner" && iso($0.occurrence) == "2026-09-10" })
        #expect(items.contains { $0.title == "Class" && iso($0.occurrence) == "2026-09-08" })
        #expect(items.contains { $0.title == "Class" && iso($0.occurrence) == "2026-09-15" })
    }

    @Test("events are expanded only within the display range, not the overdue lookback")
    func eventsIgnoreLookback() {
        // Inside the 90-day lookback but before the 14-day display window.
        let old = Event(title: "Old event", start: d("2026-08-01"))

        #expect(build(events: [old]).isEmpty)
    }

    // MARK: - Sorting

    @Test("overdue rows sort before today's normal rows, ordered by their real occurrence, then normal by time, then completed")
    func sortOrderWithinToday() {
        let overdueLate = Reminder(id: "o2", title: "Overdue B", dueDate: dt("2026-09-18", hour: 9, minute: 0))
        let overdueEarly = Reminder(id: "o1", title: "Overdue A", dueDate: dt("2026-09-10", hour: 18, minute: 0))
        // Earlier time-of-day than either overdue item's occurrence; must still sort after them.
        let earlyEvent = Event(id: "e1", title: "Early event", start: dt("2026-09-20", hour: 0, minute: 30))
        let lateReminder = Reminder(id: "r1", title: "Late reminder", dueDate: dt("2026-09-20", hour: 14, minute: 0))
        let completed = Reminder(id: "c1", title: "Completed", dueDate: dt("2026-09-20", hour: 7, minute: 0), isCompleted: true)
        let tomorrow = Event(id: "e2", title: "Tomorrow", start: dt("2026-09-21", hour: 6, minute: 0))

        let items = build(events: [tomorrow, earlyEvent], reminders: [completed, lateReminder, overdueLate, overdueEarly])

        #expect(items.map(\.title) == ["Overdue A", "Overdue B", "Early event", "Late reminder", "Completed", "Tomorrow"])
        #expect(items.prefix(2).allSatisfy { $0.isOverdue })
    }

    @Test("the sort is a deterministic total order: input order never matters, ties break on id")
    func deterministicOrder() {
        let time = dt("2026-09-22", hour: 9, minute: 0)
        let a = Reminder(id: "a", title: "Same time A", dueDate: time)
        let b = Reminder(id: "b", title: "Same time B", dueDate: time)
        let e = Event(id: "e", title: "Same time E", start: time)
        let overdueA = Reminder(id: "oa", title: "Overdue A", dueDate: d("2026-09-15"))
        let overdueB = Reminder(id: "ob", title: "Overdue B", dueDate: d("2026-09-15"))

        let forward = build(events: [e], reminders: [a, b, overdueA, overdueB])
        let backward = build(events: [e], reminders: [overdueB, overdueA, b, a])

        #expect(forward.map(\.id) == backward.map(\.id))
        // Overdue pair first (tie on occurrence => id), then the three same-time rows by id.
        #expect(forward.map(\.title) == ["Overdue A", "Overdue B", "Same time A", "Same time B", "Same time E"])
    }
}
