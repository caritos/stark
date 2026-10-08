// ios/Tests/StarkKitTests/WeeklyReviewTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("WeeklyReview")
struct WeeklyReviewTests {
    private let cal = Calendar(identifier: .gregorian)

    private func newYork() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func dt(_ iso: String, hour: Int = 12, minute: Int = 0, calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? cal
        let c = DateMath.components(iso)
        return calendar.date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: hour, minute: minute))!
    }

    private func iso(_ date: Date, calendar: Calendar? = nil) -> String {
        let calendar = calendar ?? cal
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return DateMath.isoDate(year: c.year!, month0: c.month! - 1, day: c.day!)
    }

    // 2026-09-20 is a Sunday, 09-21 a Monday, 09-26 a Saturday.

    @Test("on a Monday the default week is last week (starting the previous Sunday)")
    func defaultMonday() {
        let start = WeeklyReview.defaultWeekStart(today: dt("2026-09-21", hour: 9))
        #expect(iso(start) == "2026-09-13")
        #expect(start == cal.startOfDay(for: start))
    }

    @Test("on a Sunday the default week is the week starting that day")
    func defaultSunday() {
        #expect(iso(WeeklyReview.defaultWeekStart(today: dt("2026-09-20", hour: 23))) == "2026-09-20")
    }

    @Test("on a Saturday the default week is the current week")
    func defaultSaturday() {
        #expect(iso(WeeklyReview.defaultWeekStart(today: dt("2026-09-26", hour: 1))) == "2026-09-20")
    }

    @Test("on a Tuesday the default week is the current week")
    func defaultTuesday() {
        #expect(iso(WeeklyReview.defaultWeekStart(today: dt("2026-09-22"))) == "2026-09-20")
    }

    @Test("default week across the fall-back DST week (New York, 2026-11-01)")
    func defaultDST() {
        let ny = newYork()
        // Monday 2026-11-02 -> last week, starting Sunday 10-25.
        let monday = WeeklyReview.defaultWeekStart(today: dt("2026-11-02", hour: 8, calendar: ny), calendar: ny)
        #expect(iso(monday, calendar: ny) == "2026-10-25")
        let wednesday = WeeklyReview.defaultWeekStart(today: dt("2026-11-04", hour: 8, calendar: ny), calendar: ny)
        #expect(iso(wednesday, calendar: ny) == "2026-11-01")
        #expect(wednesday == ny.startOfDay(for: wednesday))
    }

    @Test("range runs from start of Sunday to the last second of Saturday")
    func rangeBounds() {
        let start = dt("2026-09-20", hour: 0)
        let range = WeeklyReview.range(forWeekStarting: start)
        #expect(range.lowerBound == start)
        #expect(range.upperBound == cal.startOfDay(for: dt("2026-09-27")).addingTimeInterval(-1))
        #expect(range.contains(dt("2026-09-26", hour: 23, minute: 59)))
        #expect(!range.contains(dt("2026-09-27", hour: 0)))
    }

    @Test("range in a DST fall-back week is 7 calendar days (169 hours) and ends on Saturday")
    func rangeDST() {
        let ny = newYork()
        let start = dt("2026-11-01", hour: 0, calendar: ny)
        let range = WeeklyReview.range(forWeekStarting: start, calendar: ny)
        #expect(range.upperBound.timeIntervalSince(range.lowerBound) == 7 * 86_400 + 3_600 - 1)
        #expect(ny.startOfDay(for: range.upperBound.addingTimeInterval(1)) == dt("2026-11-08", hour: 0, calendar: ny))
    }

    @Test("range in a DST spring-forward week ends on Saturday")
    func rangeSpringForward() {
        let ny = newYork()
        let start = dt("2026-03-08", hour: 0, calendar: ny)
        let range = WeeklyReview.range(forWeekStarting: start, calendar: ny)
        #expect(iso(range.upperBound, calendar: ny) == "2026-03-14")
        #expect(ny.component(.hour, from: range.upperBound) == 23)
    }

    @Test("paging steps whole weeks, across DST and month boundaries")
    func paging() {
        #expect(iso(WeeklyReview.weekStart(after: dt("2026-09-27", hour: 0))) == "2026-10-04")
        #expect(iso(WeeklyReview.weekStart(before: dt("2026-10-04", hour: 0))) == "2026-09-27")
        let ny = newYork()
        let next = WeeklyReview.weekStart(after: dt("2026-11-01", hour: 0, calendar: ny), calendar: ny)
        #expect(next == dt("2026-11-08", hour: 0, calendar: ny))
        let prev = WeeklyReview.weekStart(before: dt("2026-11-08", hour: 0, calendar: ny), calendar: ny)
        #expect(prev == dt("2026-11-01", hour: 0, calendar: ny))
    }

    // MARK: - Summary

    private func summary(events: [Event] = [], reminders: [Reminder] = [], week: String, now: String) -> WeeklyReview {
        WeeklyReview.summary(events: events, reminders: reminders, weekStarting: dt(week, hour: 0), today: dt(now, hour: 10))
    }

    @Test("completed and open reminders are bucketed by due date within the week, sorted by occurrence")
    func bucketing() {
        let done2 = Reminder(id: "d2", title: "Done late", dueDate: dt("2026-09-25"), isCompleted: true, completedDate: dt("2026-09-25"))
        let done1 = Reminder(id: "d1", title: "Done early", dueDate: dt("2026-09-21"), isCompleted: true, completedDate: dt("2026-09-21"))
        let open = Reminder(id: "o1", title: "Open", dueDate: dt("2026-09-24"))
        let outside = Reminder(id: "x", title: "Next week", dueDate: dt("2026-09-28"))
        let doneOutside = Reminder(id: "y", title: "Old", dueDate: dt("2026-09-19"), isCompleted: true, completedDate: dt("2026-09-19"))

        let s = summary(reminders: [done2, done1, open, outside, doneOutside], week: "2026-09-20", now: "2026-09-27")

        #expect(s.completed.map(\.title) == ["Done early", "Done late"])
        #expect(s.open.map(\.title) == ["Open"])
    }

    @Test("a week boundary: Saturday 23:59 is in, next Sunday 00:00 is out")
    func boundaries() {
        let inReminder = Reminder(id: "a", title: "In", dueDate: dt("2026-09-26", hour: 23, minute: 59))
        let outReminder = Reminder(id: "b", title: "Out", dueDate: dt("2026-09-27", hour: 0))
        let first = Reminder(id: "c", title: "First", dueDate: dt("2026-09-20", hour: 0))
        let s = summary(reminders: [inReminder, outReminder, first], week: "2026-09-20", now: "2026-09-27")
        #expect(Set(s.open.map(\.title)) == ["In", "First"])
    }

    @Test("an overdue-pinned reminder is bucketed by its real occurrence, not today")
    func overduePinned() {
        let missed = Reminder(id: "m", title: "Missed Tuesday", dueDate: dt("2026-09-22"))
        // Today is two weeks later: the row is pinned to today, but belongs to the Tuesday week.
        let past = summary(reminders: [missed], week: "2026-09-20", now: "2026-10-05")
        #expect(past.open.map(\.title) == ["Missed Tuesday"])
        #expect(past.open.first?.isOverdue == true)
        let current = summary(reminders: [missed], week: "2026-10-04", now: "2026-10-05")
        #expect(current.open.isEmpty)
    }

    @Test("a recurring reminder's completed copy counts as completed")
    func recurringCompletedCopy() {
        let master = Reminder(id: "m", title: "Weekly", dueDate: dt("2026-09-21"), recurrence: RecurrenceRule(frequency: .weekly), exceptionDates: [dt("2026-09-21")])
        let copy = Reminder(id: "c", title: "Weekly", dueDate: dt("2026-09-21"), isCompleted: true, completedDate: dt("2026-09-21"))
        let s = summary(reminders: [master, copy], week: "2026-09-20", now: "2026-09-23")
        #expect(s.completed.count == 1)
        #expect(s.completed.first?.occurrence == dt("2026-09-21"))
        #expect(s.open.filter { $0.occurrence < dt("2026-09-27") && $0.occurrence >= dt("2026-09-20", hour: 0) }.count == s.open.count)
    }

    @Test("events attended counts attended occurrences in the week only")
    func attended() {
        let attended = Event(id: "e1", title: "Gym", start: dt("2026-09-22", hour: 18), outcomes: [EventOutcomeRecord(date: dt("2026-09-22", hour: 18), outcome: .attended)])
        let skipped = Event(id: "e2", title: "Skipped", start: dt("2026-09-23", hour: 18), outcomes: [EventOutcomeRecord(date: dt("2026-09-23", hour: 18), outcome: .skipped)])
        let plain = Event(id: "e3", title: "Plain", start: dt("2026-09-24", hour: 18))
        let other = Event(id: "e4", title: "Other week", start: dt("2026-10-01", hour: 18), outcomes: [EventOutcomeRecord(date: dt("2026-10-01", hour: 18), outcome: .attended)])
        let s = summary(events: [attended, skipped, plain, other], week: "2026-09-20", now: "2026-10-05")
        #expect(s.attendedEventCount == 1)
        #expect(s.completed.isEmpty && s.open.isEmpty)
    }

    @Test("a week straddling a month boundary includes both months")
    func monthBoundary() {
        let a = Reminder(id: "a", title: "Sep 30", dueDate: dt("2026-09-30"))
        let b = Reminder(id: "b", title: "Oct 2", dueDate: dt("2026-10-02"))
        let s = summary(reminders: [b, a], week: "2026-09-27", now: "2026-09-28")
        #expect(s.open.map(\.title) == ["Sep 30", "Oct 2"])
        #expect(iso(s.range.upperBound) == "2026-10-03")
    }

    @Test("the load range covers the week and the overdue lookback from today")
    func loadRange() {
        let week = dt("2026-09-20", hour: 0)
        let now = dt("2026-10-05", hour: 10)
        let r = WeeklyReview.loadRange(forWeekStarting: week, today: now)
        #expect(r.lowerBound <= week)
        #expect(r.upperBound == WeeklyReview.range(forWeekStarting: week).upperBound)
        let lookback = cal.date(byAdding: .day, value: -AgendaWindow.overdueLookbackDays, to: cal.startOfDay(for: now))!
        #expect(r.lowerBound <= lookback)
        let future = WeeklyReview.loadRange(forWeekStarting: dt("2026-12-06", hour: 0), today: now)
        #expect(future.lowerBound <= lookback)
        #expect(future.upperBound >= dt("2026-12-12"))
    }
}
