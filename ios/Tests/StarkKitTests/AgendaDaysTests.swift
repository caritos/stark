// ios/Tests/StarkKitTests/AgendaDaysTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("AgendaDays")
struct AgendaDaysTests {
    private let cal = Calendar(identifier: .gregorian)

    /// Noon on the given ISO day (`DateMath.date(from:)`).
    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }

    private func dt(_ iso: String, hour: Int, minute: Int = 0, calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? cal
        let c = DateMath.components(iso)
        return calendar.date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: hour, minute: minute))!
    }

    private func eventItem(_ id: String, at date: Date) -> AgendaItem {
        AgendaItem(kind: .event(Event(id: id, title: id, start: date)), occurrence: date, displayDate: date, isOverdue: false)
    }

    private func isoDays(_ days: [AgendaDay]) -> [String] { days.map { DateMath.isoDate(from: $0.day) } }

    // MARK: - Every day is present

    @Test("with no items, every calendar day of the range still gets an entry")
    func everyDayPresentWhenEmpty() {
        let days = groupAgendaByDay([], in: d("2026-09-01")...d("2026-09-05"))

        #expect(isoDays(days) == ["2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05"])
        #expect(days.allSatisfy { $0.items.isEmpty })
        #expect(days.allSatisfy { $0.day == cal.startOfDay(for: $0.day) })
    }

    @Test("the standard 75-day display window yields 75 ascending days")
    func displayWindowHas75Days() {
        let range = AgendaWindow.range(around: d("2026-09-20"))

        let days = groupAgendaByDay([], in: range)

        #expect(days.count == 75)
        #expect(isoDays(days).first == "2026-09-06")
        #expect(isoDays(days).last == "2026-11-19")
        #expect(days.map(\.day) == days.map(\.day).sorted())
    }

    @Test("a range whose bounds fall mid-day still covers the first and last calendar days")
    func rangeBoundsAreDayGranular() {
        let days = groupAgendaByDay([], in: dt("2026-09-01", hour: 23, minute: 30)...dt("2026-09-03", hour: 0, minute: 15))

        #expect(isoDays(days) == ["2026-09-01", "2026-09-02", "2026-09-03"])
    }

    // MARK: - Grouping

    @Test("items land in the day of their displayDate")
    func itemsLandInTheirDay() {
        let a = eventItem("a", at: dt("2026-09-02", hour: 9))
        let b = eventItem("b", at: dt("2026-09-04", hour: 23, minute: 59))
        let c = eventItem("c", at: dt("2026-09-05", hour: 0, minute: 0))

        let days = groupAgendaByDay([a, b, c], in: d("2026-09-01")...d("2026-09-05"))

        #expect(days.map { $0.items.map(\.title) } == [[], ["a"], [], ["b"], ["c"]])
    }

    @Test("within a day the incoming order is preserved, even if it isn't chronological")
    func withinDayOrderPreserved() {
        let late = eventItem("late", at: dt("2026-09-02", hour: 18))
        let early = eventItem("early", at: dt("2026-09-02", hour: 8))
        let mid = eventItem("mid", at: dt("2026-09-02", hour: 12))

        let days = groupAgendaByDay([late, early, mid], in: d("2026-09-01")...d("2026-09-03"))

        #expect(days[1].items.map(\.title) == ["late", "early", "mid"])
    }

    @Test("items whose day is outside the range are dropped")
    func outOfRangeItemsDropped() {
        let before = eventItem("before", at: d("2026-08-31"))
        let inside = eventItem("inside", at: d("2026-09-02"))
        let after = eventItem("after", at: d("2026-09-06"))

        let days = groupAgendaByDay([before, inside, after], in: d("2026-09-01")...d("2026-09-05"))

        #expect(days.flatMap(\.items).map(\.title) == ["inside"])
    }

    @Test("an item late on the last day is kept even though the range ends at noon")
    func lastDayKeepsLateItems() {
        let late = eventItem("late", at: dt("2026-09-05", hour: 21))

        let days = groupAgendaByDay([late], in: d("2026-09-01")...d("2026-09-05"))

        #expect(days.last?.items.map(\.title) == ["late"])
    }

    // MARK: - DST

    private func newYork() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    @Test("a fall-back (25 hour) day still yields exactly one entry per calendar day")
    func fallBackDay() {
        let ny = newYork()
        let range = dt("2026-10-30", hour: 12, calendar: ny)...dt("2026-11-03", hour: 12, calendar: ny)
        let boundary = eventItem("boundary", at: dt("2026-11-01", hour: 23, minute: 30, calendar: ny))

        let days = groupAgendaByDay([boundary], in: range, calendar: ny)

        #expect(days.count == 5)
        let comps = days.map { ny.dateComponents([.month, .day, .hour], from: $0.day) }
        #expect(comps.map(\.day) == [30, 31, 1, 2, 3])
        #expect(comps.allSatisfy { $0.hour == 0 })
        #expect(days[2].items.map(\.title) == ["boundary"])
        #expect(days[3].items.isEmpty)
    }

    @Test("a spring-forward (23 hour) day still yields exactly one entry per calendar day")
    func springForwardDay() {
        let ny = newYork()
        let range = dt("2026-03-06", hour: 12, calendar: ny)...dt("2026-03-10", hour: 12, calendar: ny)
        let boundary = eventItem("boundary", at: dt("2026-03-08", hour: 23, minute: 30, calendar: ny))

        let days = groupAgendaByDay([boundary], in: range, calendar: ny)

        #expect(days.count == 5)
        let comps = days.map { ny.dateComponents([.month, .day, .hour], from: $0.day) }
        #expect(comps.map(\.day) == [6, 7, 8, 9, 10])
        #expect(comps.allSatisfy { $0.hour == 0 })
        #expect(days[2].items.map(\.title) == ["boundary"])
        #expect(days[3].items.isEmpty)
    }

    // MARK: - Overdue-pinned rows

    private var now: Date { dt("2026-09-20", hour: 10) }

    private func overdueItems() -> [AgendaItem] {
        let reminder = Reminder(id: "r1", title: "Pay rent", dueDate: d("2026-09-10"))
        return buildAgendaItems(events: [], reminders: [reminder], in: AgendaWindow.range(around: now), today: now)
    }

    @Test("an overdue-pinned reminder lands on today's day when today is inside the range")
    func overduePinnedLandsOnToday() {
        let items = overdueItems()
        #expect(items.first?.isOverdue == true)

        let days = groupAgendaByDay(items, in: AgendaWindow.range(around: now))

        let today = days.first { DateMath.isoDate(from: $0.day) == "2026-09-20" }
        #expect(today?.items.map(\.title) == ["Pay rent"])
        #expect(days.flatMap(\.items).count == 1)
    }

    @Test("an overdue-pinned reminder is dropped when today is outside the range")
    func overduePinnedDroppedWhenTodayOutOfRange() {
        let items = overdueItems()

        // Window re-centred on January: today (2026-09-20) is nowhere in it.
        let days = groupAgendaByDay(items, in: AgendaWindow.range(around: d("2027-01-15")))

        #expect(days.flatMap(\.items).isEmpty)
    }
}
