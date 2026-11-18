import Foundation
import Testing
@testable import StarkKit

@Suite struct WidgetAgendaTests {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }()

    private func date(_ d: Int, _ h: Int = 0, _ m: Int = 0, month: Int = 6) -> Date {
        Self.cal.date(from: DateComponents(year: 2026, month: month, day: d, hour: h, minute: m))!
    }

    private func info(_ id: String = "cal1", list: Bool = false) -> AppleCalendarInfo {
        AppleCalendarInfo(id: id, title: id, accountName: "iCloud", colorHex: "#FF0000", isReminderList: list)
    }

    private var now: Date { date(15, 10) }

    private func event(_ id: String, _ start: Date, _ end: Date?, allDay: Bool = false, cal: String = "cal1") -> AppleCalendarEvent {
        AppleCalendarEvent(id: id, title: id, notes: nil, location: nil, url: nil, start: start, end: end,
                           isAllDay: allDay, calendar: info(cal))
    }

    private func reminder(_ id: String, due: Date?, hasTime: Bool = true, done: Bool = false, list: String = "list1") -> AppleReminder {
        AppleReminder(id: id, title: id, notes: nil, due: due, dueHasTime: hasTime, isCompleted: done,
                      completedAt: nil, priority: nil, calendar: info(list, list: true))
    }

    private func items(events: [AppleCalendarEvent] = [], reminders: [AppleReminder] = [],
                       excluded: Set<String> = [], limit: Int = 10) -> [WidgetItem] {
        WidgetAgenda.items(events: events, reminders: reminders, excluded: excluded, now: now, limit: limit, calendar: Self.cal)
    }

    @Test func endedTimedEventIsDroppedRunningAndFutureKept() {
        let out = items(events: [event("ended", date(15, 8), date(15, 9)),
                                 event("running", date(15, 9), date(15, 11)),
                                 event("later", date(15, 14), date(15, 15))])
        #expect(out.map(\.id) == ["apple-running", "apple-later"])
    }

    @Test func eventEndingExactlyNowIsDropped() {
        #expect(items(events: [event("e", date(15, 9), date(15, 10))]).isEmpty)
    }

    @Test func allDayEventsComeBeforeTimedItemsOfTheSameDay() {
        let out = items(events: [event("timed", date(15, 11), date(15, 12)),
                                 event("allday", date(15), date(15), allDay: true)])
        #expect(out.map(\.id) == ["apple-allday", "apple-timed"])
        #expect(out[0].isAllDay)
    }

    @Test func multiDayAllDayEventCoveringTodayShows() {
        let out = items(events: [event("trip", date(13), date(16), allDay: true)])
        #expect(out.count == 1)
    }

    @Test func endedMultiDayAllDayEventIsDropped() {
        #expect(items(events: [event("trip", date(12), date(14), allDay: true)]).isEmpty)
    }

    @Test func tomorrowIsIncludedButNotTheDayAfter() {
        let out = items(events: [event("tom", date(16, 9), date(16, 10)),
                                 event("tomAll", date(16), date(16), allDay: true),
                                 event("after", date(17, 9), date(17, 10))])
        #expect(out.map(\.id) == ["apple-tomAll", "apple-tom"])
    }

    @Test func todaysTimedItemsSortBeforeTomorrowsAllDay() {
        let out = items(events: [event("tomAll", date(16), date(16), allDay: true),
                                 event("today", date(15, 18), date(15, 19))])
        #expect(out.map(\.id) == ["apple-today", "apple-tomAll"])
    }

    @Test func overdueRemindersOfAnyAgeComeFirstOldestFirstAndAreMarked() {
        let out = items(events: [event("e", date(15, 11), date(15, 12))],
                        reminders: [reminder("recent", due: date(14, 9)),
                                    reminder("old", due: date(1, 9, month: 1), hasTime: false)])
        #expect(out.map(\.id) == ["apple-old", "apple-recent", "apple-e"])
        #expect(out[0].isOverdue && out[1].isOverdue && !out[2].isOverdue)
    }

    @Test func manyOverdueRemindersLeaveRoomForTodaysItems() {
        let old = (1...9).map { reminder("o\($0)", due: date($0, 9, month: 1), hasTime: false) }
        let today = [event("e1", date(15, 11), date(15, 12)), event("e2", date(15, 13), date(15, 14)),
                     event("e3", date(15, 15), date(15, 16))]
        // Five rows: at most two overdue, the rest is today.
        let five = items(events: today, reminders: old, limit: 5)
        #expect(five.map(\.id) == ["apple-o1", "apple-o2", "apple-e1", "apple-e2", "apple-e3"])
        // Three rows: at most one overdue.
        let three = items(events: today, reminders: old, limit: 3)
        #expect(three.map(\.id) == ["apple-o1", "apple-e1", "apple-e2"])
    }

    @Test func overdueFillsTheRowsWhenNothingElseIsComingUp() {
        let old = (1...9).map { reminder("o\($0)", due: date($0, 9, month: 1), hasTime: false) }
        #expect(items(reminders: old, limit: 3).map(\.id) == ["apple-o1", "apple-o2", "apple-o3"])
    }

    @Test func tomorrowsItemsAreMarkedTomorrow() {
        let out = items(events: [event("today", date(15, 18), date(15, 19)),
                                 event("tom", date(16, 9), date(16, 10)),
                                 event("tomAll", date(16), date(16), allDay: true)])
        #expect(out.map(\.isTomorrow) == [false, true, true])
    }

    @Test func zeroLengthEventStartingExactlyNowIsDropped() {
        #expect(items(events: [event("z", now, now)]).isEmpty)
        #expect(items(events: [event("z", date(15, 10, 1), date(15, 10, 1))]).count == 1)
    }

    @Test func reminderDueEarlierTodayIsNotOverdue() {
        let out = items(reminders: [reminder("r", due: date(15, 8))])
        #expect(out.count == 1 && !out[0].isOverdue && out[0].isReminder)
    }

    @Test func dateOnlyReminderToday_sortsWithAllDayBeforeTimed() {
        let out = items(events: [event("timed", date(15, 11), date(15, 12))],
                        reminders: [reminder("dateonly", due: date(15, 17), hasTime: false)])
        #expect(out.map(\.id) == ["apple-dateonly", "apple-timed"])
        #expect(out[0].isAllDay)
    }

    @Test func undatedCompletedAndFutureReminders_areExcluded() {
        let out = items(reminders: [reminder("undated", due: nil), reminder("done", due: date(15, 12), done: true),
                                    reminder("tomorrow", due: date(16, 12))])
        #expect(out.isEmpty)
    }

    @Test func excludedCalendarsAndListsAreHidden() {
        let out = items(events: [event("a", date(15, 11), date(15, 12), cal: "hidden"),
                                 event("b", date(15, 12), date(15, 13))],
                        reminders: [reminder("r", due: date(15, 12), list: "hiddenList")],
                        excluded: ["hidden", "hiddenList"])
        #expect(out.map(\.id) == ["apple-b"])
    }

    @Test func limitCutsTheOrderedList() {
        let out = items(events: (0..<6).map { event("e\($0)", date(15, 11 + $0), date(15, 12 + $0)) }, limit: 3)
        #expect(out.map(\.id) == ["apple-e0", "apple-e1", "apple-e2"])
    }

    @Test func colourAndTimesAreCarried() {
        let out = items(events: [event("e", date(15, 11), date(15, 12))])
        #expect(out[0].colorHex == "#FF0000" && out[0].start == date(15, 11) && out[0].end == date(15, 12))
    }

    // MARK: refresh

    @Test func refreshIsNextBoundaryOfAShownItem() {
        let out = items(events: [event("running", date(15, 9), date(15, 10, 30)), event("later", date(15, 14), date(15, 15))])
        #expect(WidgetAgenda.nextRefresh(after: now, items: out, calendar: Self.cal) == date(15, 10, 30))
    }

    @Test func refreshIsOneHourWhenNothingIsComing() {
        #expect(WidgetAgenda.nextRefresh(after: now, items: [], calendar: Self.cal) == date(15, 11))
    }

    @Test func refreshNeverPassesTheNextMidnight() {
        let late = date(15, 23, 30)
        let out = WidgetAgenda.items(events: [], reminders: [], excluded: [], now: late, limit: 3, calendar: Self.cal)
        #expect(WidgetAgenda.nextRefresh(after: late, items: out, calendar: Self.cal) == date(16, 0))
    }

    @Test func refreshIsTheNextBoundaryEvenWhenFar() {
        let out = items(events: [event("far", date(15, 20), date(15, 21))])
        #expect(WidgetAgenda.nextRefresh(after: now, items: out, calendar: Self.cal) == date(15, 20))
    }

    @Test func timelineDatesStartNowAndFollowItemBoundaries() {
        let events = [event("a", date(15, 11), date(15, 12)), event("b", date(15, 14), date(15, 15))]
        let dates = WidgetAgenda.timelineDates(events: events, reminders: [], excluded: [], now: now,
                                               maxEntries: 10, calendar: Self.cal)
        #expect(dates.first == now)
        #expect(Array(dates.prefix(5)) == [now, date(15, 11), date(15, 12), date(15, 14), date(15, 15)])
        #expect(dates == dates.sorted())
    }

    @Test func timelineDatesAreCappedAndStrictlyIncreasing() {
        let dates = WidgetAgenda.timelineDates(events: [], reminders: [], excluded: [], now: now,
                                               maxEntries: 3, calendar: Self.cal)
        #expect(dates.count == 3)
        #expect(zip(dates, dates.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func timelineDatesStopAtTheEndOfTomorrowWindow() {
        let dates = WidgetAgenda.timelineDates(events: [], reminders: [], excluded: [], now: now,
                                               maxEntries: 100, calendar: Self.cal)
        #expect(dates.count < 100)
        #expect(dates.last! < date(17, 0))
    }
}

@Suite struct SelectionMirrorTests {
    private func suite() -> UserDefaults {
        let name = "mirror-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func missingMeansShowAll() {
        #expect(SelectionMirror.excludedIDs(from: suite()).isEmpty)
        #expect(SelectionMirror.decode(nil).isEmpty)
    }

    @Test func roundTripsThroughDefaults() {
        let d = suite()
        SelectionMirror.write(["b", "a", "c"], to: d)
        #expect(SelectionMirror.excludedIDs(from: d) == ["a", "b", "c"])
        SelectionMirror.write([], to: d)
        #expect(SelectionMirror.excludedIDs(from: d).isEmpty)
    }

    @Test func encodingIsSortedAndStable() {
        #expect(SelectionMirror.encode(["b", "a"]) == SelectionMirror.encode(["a", "b"]))
    }

    @Test func corruptDataMeansShowAll() {
        #expect(SelectionMirror.decode(Data("not json".utf8)).isEmpty)
    }
}
