// ios/Tests/StarkKitTests/TimelineLayoutTests.swift
import Testing
import Foundation
@testable import StarkKit

private let zoneIDs = ["America/New_York", "Asia/Tokyo", "Pacific/Honolulu", "UTC"]

@Suite("timelineLayout")
struct TimelineLayoutTests {
    private func cal(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }
    private func at(_ c: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    private func row(_ e: Event, _ c: Calendar, day: Date, source: AppleSource? = nil) -> AgendaItem {
        AgendaItem(kind: .event(e), occurrence: e.start, displayDate: day, isOverdue: false, appleSource: source)
    }
    private func timed(_ id: String, _ c: Calendar, _ sh: Int, _ eh: Int, day: Int = 18) -> AgendaItem {
        let e = Event(id: id, title: id, start: at(c, 2026, 11, day, sh), end: at(c, 2026, 11, day, eh))
        return row(e, c, day: at(c, 2026, 11, day))
    }
    private func layout(_ items: [AgendaItem], _ c: Calendar, day: Int = 18) -> DayTimeline {
        timelineLayout(items: items, day: at(c, 2026, 11, day), calendar: c)
    }

    @Test(arguments: zoneIDs) func allDayEventIsChip(_ z: String) {
        let c = cal(z)
        let e = Event(id: "a", title: "A", start: at(c, 2026, 11, 18), end: nil, isAllDay: true)
        let src = AppleSource(calendarID: "c", calendarTitle: "US Holidays", colorHex: nil, isReminder: false)
        let t = layout([row(e, c, day: at(c, 2026, 11, 18), source: src)], c)
        #expect(t.blocks.isEmpty && t.allDay.count == 1)
        #expect(t.allDay[0].title == "A" && t.allDay[0].isHoliday)
    }

    @Test(arguments: zoneIDs) func timedEventMinutes(_ z: String) {
        let c = cal(z)
        let e = Event(id: "a", title: "A", start: at(c, 2026, 11, 18, 9, 30), end: at(c, 2026, 11, 18, 10, 45))
        let t = layout([row(e, c, day: at(c, 2026, 11, 18))], c)
        #expect(t.allDay.isEmpty && t.blocks.count == 1)
        let b = t.blocks[0]
        #expect(b.startMinute == 570 && b.endMinute == 645 && b.column == 0 && b.columnCount == 1)
        #expect(!b.isReminder && !b.isCompleted)
    }

    @Test(arguments: zoneIDs) func crossingMidnightClipsBothDays(_ z: String) {
        let c = cal(z)
        let e = Event(id: "a", title: "A", start: at(c, 2026, 11, 18, 22), end: at(c, 2026, 11, 19, 2))
        let one = layout([row(e, c, day: at(c, 2026, 11, 18))], c, day: 18)
        let two = layout([row(e, c, day: at(c, 2026, 11, 19))], c, day: 19)
        #expect(one.blocks.map(\.startMinute) == [1320] && one.blocks.map(\.endMinute) == [1440])
        #expect(two.blocks.map(\.startMinute) == [0] && two.blocks.map(\.endMinute) == [120])
    }

    @Test(arguments: zoneIDs) func endAtMidnightNotNextDay(_ z: String) {
        let c = cal(z)
        let e = Event(id: "a", title: "A", start: at(c, 2026, 11, 18, 22), end: at(c, 2026, 11, 19, 0))
        let src = AppleSource(calendarID: "c", calendarTitle: "Work", colorHex: nil, isReminder: false)
        let next = layout([row(e, c, day: at(c, 2026, 11, 19), source: src)], c, day: 19)
        #expect(next.blocks.isEmpty && next.allDay.isEmpty)
        let same = layout([row(e, c, day: at(c, 2026, 11, 18), source: src)], c, day: 18)
        #expect(same.blocks.map(\.endMinute) == [1440])
    }

    @Test(arguments: zoneIDs) func zeroLengthGetsFifteenMinutes(_ z: String) {
        let c = cal(z)
        let zero = Event(id: "z", title: "z", start: at(c, 2026, 11, 18, 9), end: at(c, 2026, 11, 18, 9))
        let backwards = Event(id: "b", title: "b", start: at(c, 2026, 11, 18, 12), end: at(c, 2026, 11, 18, 11))
        let none = Event(id: "n", title: "n", start: at(c, 2026, 11, 18, 14), end: nil)
        let late = Event(id: "l", title: "l", start: at(c, 2026, 11, 18, 23, 55), end: nil)
        let d = at(c, 2026, 11, 18)
        let t = layout([row(zero, c, day: d), row(backwards, c, day: d), row(none, c, day: d), row(late, c, day: d)], c)
        let byID = Dictionary(uniqueKeysWithValues: t.blocks.map { ($0.title, $0) })
        #expect(byID["z"]!.endMinute - byID["z"]!.startMinute == 15)
        #expect(byID["b"]!.startMinute == 720 && byID["b"]!.endMinute == 735)
        #expect(byID["n"]!.endMinute == 855)
        #expect(byID["l"]!.endMinute == 1440 && byID["l"]!.endMinute - byID["l"]!.startMinute >= 15)
    }

    @Test(arguments: zoneIDs) func overlapSharesColumns(_ z: String) {
        let c = cal(z)
        let t = layout([timed("A", c, 9, 11), timed("B", c, 10, 12), timed("C", c, 11, 12)], c)
        let b = Dictionary(uniqueKeysWithValues: t.blocks.map { ($0.title, $0) })
        #expect(b["A"]!.column == 0 && b["B"]!.column == 1 && b["C"]!.column == 0)
        #expect(t.blocks.allSatisfy { $0.columnCount == 2 })
    }

    @Test(arguments: zoneIDs) func touchingEventsDoNotShareColumns(_ z: String) {
        let c = cal(z)
        let t = layout([timed("A", c, 9, 10), timed("B", c, 10, 11)], c)
        #expect(t.blocks.allSatisfy { $0.column == 0 && $0.columnCount == 1 })
    }

    @Test(arguments: zoneIDs) func timedReminderIsThirtyMinuteBlock(_ z: String) {
        let c = cal(z)
        let r = Reminder(id: "r", title: "R", dueDate: at(c, 2026, 11, 18, 8, 15), isCompleted: true)
        let item = AgendaItem(kind: .reminder(r), occurrence: r.dueDate!, displayDate: at(c, 2026, 11, 18), isOverdue: false)
        let t = layout([item], c)
        #expect(t.blocks.count == 1)
        let b = t.blocks[0]
        #expect(b.isReminder && b.isCompleted && b.startMinute == 495 && b.endMinute == 525)
        let late = Reminder(id: "l", title: "L", dueDate: at(c, 2026, 11, 18, 23, 50))
        let t2 = layout([AgendaItem(kind: .reminder(late), occurrence: late.dueDate!,
                                    displayDate: at(c, 2026, 11, 18), isOverdue: false)], c)
        #expect(t2.blocks[0].endMinute == 1440 && t2.blocks[0].endMinute - t2.blocks[0].startMinute >= 15)
    }

    @Test(arguments: zoneIDs) func dateOnlyReminderIsChip(_ z: String) {
        let c = cal(z)
        let d = at(c, 2026, 11, 18)
        let r = Reminder(id: "r", title: "R", dueDate: d)
        let t = layout([AgendaItem(kind: .reminder(r), occurrence: d, displayDate: d, isOverdue: false)], c)
        #expect(t.blocks.isEmpty && t.allDay.map(\.title) == ["R"])
    }

    @Test func dstDayUsesWallClockMinutes() {
        let c = cal("America/New_York")  // 2026-03-08 spring forward
        let e = Event(id: "a", title: "A", start: at(c, 2026, 3, 8, 9), end: at(c, 2026, 3, 8, 10))
        let late = Event(id: "b", title: "B", start: at(c, 2026, 3, 8, 23), end: at(c, 2026, 3, 9, 1))
        let d = at(c, 2026, 3, 8)
        let t = timelineLayout(items: [row(e, c, day: d), row(late, c, day: d)], day: d, calendar: c)
        let b = Dictionary(uniqueKeysWithValues: t.blocks.map { ($0.title, $0) })
        #expect(b["A"]!.startMinute == 540 && b["A"]!.endMinute == 600)
        #expect(b["B"]!.startMinute == 1380 && b["B"]!.endMinute == 1440)
        // Fall back day (25 hours).
        let f = at(c, 2026, 11, 1)
        let fe = Event(id: "f", title: "F", start: at(c, 2026, 11, 1, 9), end: at(c, 2026, 11, 1, 10))
        let t2 = timelineLayout(items: [row(fe, c, day: f)], day: f, calendar: c)
        #expect(t2.blocks[0].startMinute == 540 && t2.blocks[0].endMinute == 600)
    }

    @Test(arguments: zoneIDs) func tenOverlapsHaveTenColumns(_ z: String) {
        let c = cal(z)
        let t = layout((0..<10).map { timed("e\($0)", c, 9, 10) }, c)
        #expect(t.blocks.count == 10)
        #expect(Set(t.blocks.map(\.column)) == Set(0..<10))
        #expect(t.blocks.allSatisfy { $0.columnCount == 10 })
    }

    @Test(arguments: zoneIDs) func otherDaysIgnored(_ z: String) {
        let c = cal(z)
        let t = layout([timed("A", c, 9, 10, day: 19), timed("B", c, 9, 10, day: 17)], c)
        #expect(t.blocks.isEmpty && t.allDay.isEmpty)
    }

    @Test(arguments: zoneIDs) func emptyDay(_ z: String) {
        let c = cal(z)
        #expect(layout([], c) == DayTimeline(allDay: [], blocks: []))
    }

    @Test(arguments: zoneIDs) func middleDayOfMultiDayTimedEventIsChip(_ z: String) {
        let c = cal(z)
        let e = Event(id: "m", title: "M", start: at(c, 2026, 11, 17, 10), end: at(c, 2026, 11, 19, 15))
        let t = layout([row(e, c, day: at(c, 2026, 11, 18))], c)
        #expect(t.blocks.isEmpty && t.allDay.map(\.title) == ["M"])
    }
}
