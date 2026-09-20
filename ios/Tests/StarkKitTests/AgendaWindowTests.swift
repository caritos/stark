// ios/Tests/StarkKitTests/AgendaWindowTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("AgendaWindow")
struct AgendaWindowTests {
    private let cal = Calendar(identifier: .gregorian)

    private func newYork() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func dt(_ iso: String, hour: Int, minute: Int = 0, second: Int = 0, calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? cal
        let c = DateMath.components(iso)
        return calendar.date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: hour, minute: minute, second: second))!
    }

    private func isoDay(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return DateMath.isoDate(year: c.year!, month0: c.month! - 1, day: c.day!)
    }

    @Test("the display range is a subset of the load range, and both include today")
    func displayRangeIsSubsetOfLoadRange() {
        let today = DateMath.date(from: "2026-09-20")
        let display = AgendaWindow.range(around: today)
        let load = AgendaWindow.loadRange(around: today)

        #expect(load.lowerBound <= display.lowerBound)
        #expect(load.upperBound >= display.upperBound)
        #expect(display.contains(today))
        #expect(load.contains(today))
    }

    @Test("the display range contains every moment of today, whatever the time of day")
    func displayRangeContainsAllOfToday() {
        for hour in [0, 12, 23] {
            let now = dt("2026-09-20", hour: hour, minute: hour == 23 ? 59 : 0)
            let display = AgendaWindow.range(around: now)
            #expect(display.contains(now))
            #expect(display.contains(dt("2026-09-20", hour: 0)))
            #expect(display.contains(dt("2026-09-20", hour: 23, minute: 59)))
        }
    }

    @Test("the load range starts at the beginning of the day overdueLookbackDays back and ends at the end of the day daysAfter ahead")
    func loadRangeBounds() {
        let today = DateMath.date(from: "2026-09-20")
        let load = AgendaWindow.loadRange(around: today)

        #expect(load.lowerBound == dt("2026-06-22", hour: 0))
        #expect(load.upperBound == dt("2026-11-19", hour: 23, minute: 59, second: 59))
    }

    @Test("the display range is 14 days back through 60 days forward, first day's start to last day's end")
    func displayRangeBounds() {
        let today = DateMath.date(from: "2026-09-20")
        let display = AgendaWindow.range(around: today)

        #expect(display.lowerBound == dt("2026-09-06", hour: 0))
        #expect(display.upperBound == dt("2026-11-19", hour: 23, minute: 59, second: 59))
    }

    @Test("the display range doesn't depend on the time of day of the date it is built around")
    func displayRangeIgnoresTimeOfDay() {
        let morning = AgendaWindow.range(around: dt("2026-09-20", hour: 0, minute: 5))
        let night = AgendaWindow.range(around: dt("2026-09-20", hour: 23, minute: 55))

        #expect(morning == night)
        #expect(AgendaWindow.loadRange(around: dt("2026-09-20", hour: 0, minute: 5)) == AgendaWindow.loadRange(around: dt("2026-09-20", hour: 23, minute: 55)))
    }

    // MARK: - Events at the edges of the window

    @Test("an early-morning event on the first day and an evening event on the last day are both in the agenda")
    func edgeDayEventsAreKept() {
        let today = dt("2026-09-20", hour: 10)
        let display = AgendaWindow.range(around: today)
        let first = Event(id: "first", title: "First day 08:00", start: dt("2026-09-06", hour: 8))
        let last = Event(id: "last", title: "Last day 20:00", start: dt("2026-11-19", hour: 20))

        let items = buildAgendaItems(events: [first, last], reminders: [], in: display, today: today)

        #expect(Set(items.map(\.title)) == ["First day 08:00", "Last day 20:00"])
    }

    @Test("events just outside the window are still excluded")
    func eventsJustOutsideAreExcluded() {
        let today = dt("2026-09-20", hour: 10)
        let display = AgendaWindow.range(around: today)
        let before = Event(id: "before", title: "Day before", start: dt("2026-09-05", hour: 23, minute: 59))
        let after = Event(id: "after", title: "Day after", start: dt("2026-11-20", hour: 0, minute: 0))

        let items = buildAgendaItems(events: [before, after], reminders: [], in: display, today: today)

        #expect(items.isEmpty)
    }

    @Test("edge-day events land under the first and last day's headers")
    func edgeDayEventsGroupIntoEdgeDays() {
        let today = dt("2026-09-20", hour: 10)
        let display = AgendaWindow.range(around: today)
        let first = Event(id: "first", title: "First day 08:00", start: dt("2026-09-06", hour: 8))
        let last = Event(id: "last", title: "Last day 20:00", start: dt("2026-11-19", hour: 20))

        let items = buildAgendaItems(events: [first, last], reminders: [], in: display, today: today)
        let days = groupAgendaByDay(items, in: display)

        #expect(days.first?.items.map(\.title) == ["First day 08:00"])
        #expect(days.last?.items.map(\.title) == ["Last day 20:00"])
    }

    // MARK: - Day count and DST

    @Test("the display range still groups into exactly 75 days")
    func displayRangeHas75Days() {
        let days = groupAgendaByDay([], in: AgendaWindow.range(around: dt("2026-09-20", hour: 10)))

        #expect(days.count == 75)
        #expect(days.map { DateMath.isoDate(from: $0.day) }.first == "2026-09-06")
        #expect(days.map { DateMath.isoDate(from: $0.day) }.last == "2026-11-19")
    }

    @Test("a window spanning the fall-back day (2026-11-01, New York) is 75 days from midnight to 23:59:59")
    func windowAcrossFallBack() {
        let ny = newYork()
        let range = AgendaWindow.range(around: dt("2026-10-20", hour: 12, calendar: ny), calendar: ny)

        #expect(groupAgendaByDay([], in: range, calendar: ny).count == 75)
        #expect(range.lowerBound == dt("2026-10-06", hour: 0, calendar: ny))
        #expect(range.upperBound == dt("2026-12-19", hour: 23, minute: 59, second: 59, calendar: ny))
    }

    @Test("a window whose first day is the 25-hour fall-back day starts at its midnight and is 75 days")
    func windowStartingOnFallBackDay() {
        let ny = newYork()
        // today 2026-11-15 -> first day 2026-11-01.
        let range = AgendaWindow.range(around: dt("2026-11-15", hour: 12, calendar: ny), calendar: ny)

        #expect(range.lowerBound == dt("2026-11-01", hour: 0, calendar: ny))
        #expect(isoDay(range.lowerBound, calendar: ny) == "2026-11-01")
        #expect(isoDay(range.upperBound, calendar: ny) == "2027-01-14")
        #expect(groupAgendaByDay([], in: range, calendar: ny).count == 75)
    }

    @Test("a window whose last day is the 25-hour fall-back day ends at 23:59:59 that day and is 75 days")
    func windowEndingOnFallBackDay() {
        let ny = newYork()
        // today 2026-09-02 -> last day 2026-11-01.
        let range = AgendaWindow.range(around: dt("2026-09-02", hour: 12, calendar: ny), calendar: ny)

        #expect(range.upperBound == dt("2026-11-01", hour: 23, minute: 59, second: 59, calendar: ny))
        #expect(isoDay(range.upperBound, calendar: ny) == "2026-11-01")
        #expect(groupAgendaByDay([], in: range, calendar: ny).count == 75)
    }

    @Test("a window across the spring-forward day (2026-03-08, New York) is also 75 days")
    func windowAcrossSpringForward() {
        let ny = newYork()
        let range = AgendaWindow.range(around: dt("2026-03-01", hour: 12, calendar: ny), calendar: ny)

        #expect(groupAgendaByDay([], in: range, calendar: ny).count == 75)
        #expect(isoDay(range.lowerBound, calendar: ny) == "2026-02-15")
        #expect(isoDay(range.upperBound, calendar: ny) == "2026-04-30")
    }

    // MARK: - refreshedAnchor (following the calendar past midnight)

    private func zone(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    @Test("same calendar day: the anchor is left exactly as it was")
    func refreshSameDayUnchanged() {
        let seen = dt("2026-09-20", hour: 9)
        let now = dt("2026-09-20", hour: 23, minute: 59)

        // Following today...
        #expect(AgendaWindow.refreshedAnchor(current: seen, lastSeenToday: seen, now: now) == seen)
        // ...or re-centred elsewhere.
        let elsewhere = dt("2027-01-15", hour: 12)
        #expect(AgendaWindow.refreshedAnchor(current: elsewhere, lastSeenToday: seen, now: now) == elsewhere)
    }

    @Test("new day while following today: the anchor moves to the new today")
    func refreshNewDayFollowingMovesAnchor() {
        let seen = dt("2026-09-20", hour: 9)
        let now = dt("2026-09-21", hour: 0, minute: 1)

        #expect(AgendaWindow.refreshedAnchor(current: seen, lastSeenToday: seen, now: now) == now)
    }

    @Test("following is judged by the anchor's day, not its time of day")
    func refreshFollowingIgnoresTimeOfDay() {
        let seen = dt("2026-09-20", hour: 9)
        // A re-centre onto today stores a noon anchor.
        let noonAnchor = dt("2026-09-20", hour: 12)
        let now = dt("2026-09-21", hour: 8)

        #expect(AgendaWindow.refreshedAnchor(current: noonAnchor, lastSeenToday: seen, now: now) == now)
    }

    @Test("new day but the user re-centred elsewhere: the anchor is left alone")
    func refreshNewDayRecentredUnchanged() {
        let seen = dt("2026-09-20", hour: 9)
        let elsewhere = dt("2027-01-15", hour: 12)
        let now = dt("2026-09-21", hour: 0, minute: 1)

        #expect(AgendaWindow.refreshedAnchor(current: elsewhere, lastSeenToday: seen, now: now) == elsewhere)
    }

    @Test("an anchor on yesterday (not the last-seen today) is not following")
    func refreshAnchorOnAnotherRecentDayUnchanged() {
        let seen = dt("2026-09-20", hour: 9)
        let yesterday = dt("2026-09-19", hour: 12)
        let now = dt("2026-09-21", hour: 9)

        #expect(AgendaWindow.refreshedAnchor(current: yesterday, lastSeenToday: seen, now: now) == yesterday)
    }

    @Test("several days later (app left in the background) still moves a following anchor to the new today")
    func refreshAfterSeveralDays() {
        let seen = dt("2026-09-20", hour: 9)
        let now = dt("2026-09-25", hour: 7)

        #expect(AgendaWindow.refreshedAnchor(current: seen, lastSeenToday: seen, now: now) == now)
    }

    @Test("the fall-back day (25 hours, New York) is one day: no move at 00:30, at the repeated 01:30, or at 23:30")
    func refreshWithinFallBackDay() {
        let ny = newYork()
        let seen = dt("2026-11-01", hour: 0, minute: 30, calendar: ny)
        // 01:30 happens twice; the second (EST) one is an hour after the first.
        let secondOneThirty = dt("2026-11-01", hour: 1, minute: 30, calendar: ny).addingTimeInterval(3600)
        let lateEvening = dt("2026-11-01", hour: 23, minute: 30, calendar: ny)

        #expect(AgendaWindow.refreshedAnchor(current: seen, lastSeenToday: seen, now: secondOneThirty, calendar: ny) == seen)
        #expect(AgendaWindow.refreshedAnchor(current: seen, lastSeenToday: seen, now: lateEvening, calendar: ny) == seen)
    }

    @Test("crossing midnight into and out of the fall-back day moves a following anchor")
    func refreshAcrossFallBackMidnights() {
        let ny = newYork()
        let beforeMidnight = dt("2026-10-31", hour: 23, minute: 30, calendar: ny)
        let afterMidnight = dt("2026-11-01", hour: 0, minute: 10, calendar: ny)
        let nextDay = dt("2026-11-02", hour: 0, minute: 10, calendar: ny)

        #expect(AgendaWindow.refreshedAnchor(current: beforeMidnight, lastSeenToday: beforeMidnight, now: afterMidnight, calendar: ny) == afterMidnight)
        #expect(AgendaWindow.refreshedAnchor(current: afterMidnight, lastSeenToday: afterMidnight, now: nextDay, calendar: ny) == nextDay)
    }

    @Test("a spring-forward night (New York) still counts as exactly one day change")
    func refreshAcrossSpringForward() {
        let ny = newYork()
        let saturdayNight = dt("2026-03-07", hour: 23, minute: 30, calendar: ny)
        let sundayMorning = dt("2026-03-08", hour: 3, minute: 5, calendar: ny)

        #expect(AgendaWindow.refreshedAnchor(current: saturdayNight, lastSeenToday: saturdayNight, now: sundayMorning, calendar: ny) == sundayMorning)
    }

    @Test("a timezone change that moves the local date forward counts as a new day for a following anchor")
    func refreshAfterTimezoneChange() {
        // 14:00 in Los Angeles is 23:00 in Paris the same evening; an hour later, in Paris it is
        // already the next calendar day.
        let seenInLA = dt("2026-09-20", hour: 14, calendar: zone("America/Los_Angeles"))
        let now = dt("2026-09-20", hour: 15, calendar: zone("America/Los_Angeles"))
        let paris = zone("Europe/Paris")
        #expect(paris.isDate(seenInLA, inSameDayAs: now) == false)

        #expect(AgendaWindow.refreshedAnchor(current: seenInLA, lastSeenToday: seenInLA, now: now, calendar: paris) == now)
        // In Los Angeles the same two instants are one day: nothing moves.
        #expect(AgendaWindow.refreshedAnchor(current: seenInLA, lastSeenToday: seenInLA, now: now, calendar: zone("America/Los_Angeles")) == seenInLA)
    }

    @Test("the refreshed anchor's window covers the new today")
    func refreshedWindowContainsNewToday() {
        let seen = dt("2026-09-20", hour: 9)
        let now = dt("2026-09-21", hour: 0, minute: 1)

        let anchor = AgendaWindow.refreshedAnchor(current: seen, lastSeenToday: seen, now: now)

        #expect(AgendaWindow.range(around: anchor).contains(now))
        #expect(AgendaWindow.loadRange(around: anchor).contains(now))
    }

    @Test("the load range across a DST change is a superset of the display range and covers the same months")
    func loadRangeAcrossDST() {
        let ny = newYork()
        let today = dt("2026-10-20", hour: 12, calendar: ny)
        let display = AgendaWindow.range(around: today, calendar: ny)
        let load = AgendaWindow.loadRange(around: today, calendar: ny)

        #expect(load.lowerBound <= display.lowerBound)
        #expect(load.upperBound >= display.upperBound)
        #expect(load.lowerBound == dt("2026-07-22", hour: 0, calendar: ny))
    }
}
