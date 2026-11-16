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

/// Review fixes (stage 4a): real occurrence intervals for repeating and overnight events, the
/// Day/Week item range, chip flags and the real times behind clamped blocks.
/// Local series expand in the process time zone (as `buildAgendaItems` does), so those tests use
/// the default calendar; run the suite under TZ=America/New_York, Asia/Tokyo, Pacific/Honolulu, UTC.
@Suite("timelineLayout review fixes")
struct TimelineLayoutFixTests {
    private let c = Calendar(identifier: .gregorian)
    private func at(_ d: Int, _ h: Int = 0, _ m: Int = 0, month: Int = 11) -> Date {
        c.date(from: DateComponents(year: 2026, month: month, day: d, hour: h, minute: m))!
    }
    private func dayRange(_ first: Int, _ last: Int) -> ClosedRange<Date> {
        at(first)...c.date(byAdding: .day, value: 1, to: at(last))!.addingTimeInterval(-1)
    }
    /// The Day/Week pipeline: rows for the shown days, then one day's layout.
    private func layout(events: [Event] = [], reminders: [Reminder] = [], apple: AppleSnapshot = .empty,
                        days: ClosedRange<Date>, day: Date, today: Date? = nil) -> DayTimeline {
        let items = timelineAgendaItems(events: events, reminders: reminders, plans: [], apple: apple,
                                        days: days, today: today ?? at(16, 8), calendar: c)
        return timelineLayout(items: items, day: day, calendar: c)
    }
    private func spans(_ t: DayTimeline) -> [[Int]] {
        t.blocks.map { [$0.startMinute, $0.endMinute] }.sorted { $0[0] < $1[0] }
    }

    // Nov 18 2026 is a Wednesday.
    @Test func localWeeklyOvernightShowsItsAfterMidnightPart() {
        let e = Event(id: "w", title: "W", start: at(18, 22), end: at(19, 2),
                      recurrence: RecurrenceRule(frequency: .weekly))
        let thu = layout(events: [e], days: dayRange(19, 19), day: at(19))
        #expect(spans(thu) == [[0, 120]])
        #expect(thu.blocks[0].start == at(18, 22))
        let wed = layout(events: [e], days: dayRange(18, 18), day: at(18))
        #expect(spans(wed) == [[1320, 1440]])
    }

    @Test func localDailyOvernightHasBothPartsWithUniqueIDs() {
        let e = Event(id: "d", title: "D", start: at(18, 22), end: at(19, 1),
                      recurrence: RecurrenceRule(frequency: .daily))
        let t = layout(events: [e], days: dayRange(19, 19), day: at(19))
        #expect(spans(t) == [[0, 60], [1320, 1440]])
        #expect(Set(t.blocks.map(\.id)).count == 2)
        #expect(t.blocks.allSatisfy { $0.columnCount == 1 })
        // Every block opens its own occurrence.
        let opened = t.blocks.compactMap { t.items[$0.id]?.occurrence }.sorted()
        #expect(opened == [at(18, 22), at(19, 22)])
    }

    @Test func localThreeDaySeriesClipsEndsAndChipsTheMiddle() {
        // Mon Nov 16 10:00 to Wed Nov 18 15:00, weekly.
        let e = Event(id: "c", title: "C", start: at(16, 10), end: at(18, 15),
                      recurrence: RecurrenceRule(frequency: .weekly))
        let days = dayRange(15, 21)
        #expect(spans(layout(events: [e], days: days, day: at(16))) == [[600, 1440]])
        let tue = layout(events: [e], days: days, day: at(17))
        #expect(tue.blocks.isEmpty && tue.allDay.map(\.title) == ["C"])
        #expect(spans(layout(events: [e], days: days, day: at(18))) == [[0, 900]])
        // Next week's occurrence too.
        #expect(spans(layout(events: [e], days: dayRange(22, 28), day: at(25))) == [[0, 900]])
    }

    @Test func appleDailyOvernightKeepsItsMorningPart() {
        let info = AppleCalendarInfo(id: "cal", title: "Home", accountName: "iCloud", colorHex: "#00FF00",
                                     isReminderList: false)
        let events = (16...20).map { d in
            AppleCalendarEvent(id: "sleep", title: "Sleep", notes: nil, location: nil, url: nil,
                               start: at(d, 23), end: at(d + 1, 7), isAllDay: false, calendar: info)
        }
        let snapshot = AppleSnapshot(events: events, reminders: [])
        for days in [dayRange(18, 18), dayRange(15, 21)] {
            let t = layout(apple: snapshot, days: days, day: at(18))
            #expect(spans(t) == [[0, 420], [1380, 1440]])
            #expect(Set(t.blocks.map(\.id)).count == 2)
            let opened = t.blocks.compactMap { t.items[$0.id]?.occurrence }.sorted()
            #expect(opened == [at(17, 23), at(18, 23)])
        }
    }

    @Test func repeatingReminderListedOnlyOnceInAWeek() {
        // Due today (Mon Nov 16) at 9:00, not done: the agenda lists it once, today.
        let r = Reminder(id: "r", title: "R", dueDate: at(16, 9), recurrence: RecurrenceRule(frequency: .daily))
        let days = dayRange(15, 21)
        let perDay = (15...21).map { layout(reminders: [r], days: days, day: at($0)).blocks.count }
        #expect(perDay == [0, 1, 0, 0, 0, 0, 0])
        // Day view on a later day: not listed there either.
        #expect(layout(reminders: [r], days: dayRange(18, 18), day: at(18)).blocks.isEmpty)
        // Once today's is done, only the next occurrence is listed.
        let done = Reminder(id: "r", title: "R", dueDate: at(17, 9), recurrence: RecurrenceRule(frequency: .daily))
        let next = (15...21).map { layout(reminders: [done], days: days, day: at($0)).blocks.count }
        #expect(next == [0, 0, 1, 0, 0, 0, 0])
        // A one-off in a past week still shows.
        let old = Reminder(id: "o", title: "O", dueDate: at(3, 9), isCompleted: true)
        #expect(layout(reminders: [old], days: dayRange(1, 7), day: at(3)).blocks.count == 1)
    }

    @Test func chipsSayReminderAndCompleted() {
        let d = at(18)
        let done = Reminder(id: "r", title: "R", dueDate: d, isCompleted: true)
        let open = Reminder(id: "o", title: "O", dueDate: d)
        let allDay = Event(id: "a", title: "A", start: d, isAllDay: true)
        let t = timelineLayout(items: [
            AgendaItem(kind: .reminder(done), occurrence: d, displayDate: d, isOverdue: false),
            AgendaItem(kind: .reminder(open), occurrence: d, displayDate: d, isOverdue: false),
            AgendaItem(kind: .event(allDay), occurrence: d, displayDate: d, isOverdue: false),
        ], day: d, calendar: c)
        let byTitle = Dictionary(uniqueKeysWithValues: t.allDay.map { ($0.title, $0) })
        #expect(byTitle["R"]!.isReminder && byTitle["R"]!.isCompleted)
        #expect(byTitle["O"]!.isReminder && !byTitle["O"]!.isCompleted)
        #expect(!byTitle["A"]!.isReminder && !byTitle["A"]!.isCompleted)
    }

    @Test func blocksKeepTheirRealTimesForLabels() {
        let late = Reminder(id: "l", title: "L", dueDate: at(18, 23, 50))
        let overnight = Event(id: "o", title: "O", start: at(18, 22), end: at(19, 2))
        let toMidnight = Event(id: "m", title: "M", start: at(18, 20), end: at(19))
        let rows = [
            AgendaItem(kind: .reminder(late), occurrence: at(18, 23, 50), displayDate: at(18, 23, 50), isOverdue: false),
            AgendaItem(kind: .event(overnight), occurrence: at(18, 22), displayDate: at(18, 22), isOverdue: false),
            AgendaItem(kind: .event(toMidnight), occurrence: at(18, 20), displayDate: at(18, 20), isOverdue: false),
        ]
        let wed = Dictionary(uniqueKeysWithValues: timelineLayout(items: rows, day: at(18), calendar: c)
            .blocks.map { ($0.title, $0) })
        #expect(wed["L"]!.startMinute == 1425 && wed["L"]!.start == at(18, 23, 50) && wed["L"]!.end == nil)
        #expect(wed["O"]!.start == at(18, 22) && wed["O"]!.end == at(19, 2))
        #expect(!wed["O"]!.startIsOtherDay && wed["O"]!.endIsOtherDay)
        // Ending exactly at midnight reads as this day's 12:00 AM, not another day.
        #expect(wed["M"]!.end == at(19) && !wed["M"]!.endIsOtherDay)
        let thu = timelineLayout(items: [AgendaItem(kind: .event(overnight), occurrence: at(19), displayDate: at(19),
                                                    isOverdue: false)], day: at(19), calendar: c).blocks[0]
        #expect(thu.startMinute == 0 && thu.start == at(18, 22) && thu.startIsOtherDay && !thu.endIsOtherDay)
    }

    @Test func midnightReminderIsAChip() {
        // Known behaviour: a reminder due at exactly 00:00 reads as date-only.
        let r = Reminder(id: "r", title: "R", dueDate: at(18))
        let t = timelineLayout(items: [AgendaItem(kind: .reminder(r), occurrence: at(18), displayDate: at(18),
                                                  isOverdue: false)], day: at(18), calendar: c)
        #expect(t.blocks.isEmpty && t.allDay.count == 1)
    }

    @Test func fallBackEventKeepsItsLength() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        // 2026-11-01: 1:30 EDT (05:30 UTC) to 1:15 EST (06:15 UTC) is 45 minutes.
        let start = Date(timeIntervalSince1970: 1_793_511_000)  // 2026-11-01T05:30:00Z
        let e = Event(id: "f", title: "F", start: start, end: start.addingTimeInterval(45 * 60))
        let day = ny.startOfDay(for: start)
        let t = timelineLayout(items: [AgendaItem(kind: .event(e), occurrence: start, displayDate: start, isOverdue: false)],
                               day: day, calendar: ny)
        #expect(t.blocks.map(\.startMinute) == [90])
        #expect(t.blocks.map(\.endMinute) == [135])
    }
}
