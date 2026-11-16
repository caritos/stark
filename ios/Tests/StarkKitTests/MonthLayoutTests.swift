// ios/Tests/StarkKitTests/MonthLayoutTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("monthLayout")
struct MonthLayoutTests {
    // November 2026: Nov 1 is a Sunday, so the grid's first row is Nov 1-7 (columns 0...6).
    private let month = YearMonth(year: 2026, month0: 10)
    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }
    private func at(_ iso: String, _ hour: Int) -> Date {
        Calendar(identifier: .gregorian).date(bySettingHour: hour, minute: 0, second: 0, of: d(iso))!
    }

    private func rows(_ event: Event, from: String, days: Int, source: AppleSource? = nil) -> [AgendaItem] {
        (0..<days).map { k in
            let day = d(DateMath.addDays(from, k))
            return AgendaItem(kind: .event(event), occurrence: day, displayDate: day, isOverdue: false,
                              appleSource: source)
        }
    }
    private func eventRow(_ event: Event, day: String, source: AppleSource? = nil) -> AgendaItem {
        let t = event.start
        return AgendaItem(kind: .event(event), occurrence: t, displayDate: d(day), isOverdue: false,
                          appleSource: source)
    }
    private func reminderRow(_ r: Reminder, day: String, source: AppleSource? = nil) -> AgendaItem {
        AgendaItem(kind: .reminder(r), occurrence: r.dueDate ?? d(day), displayDate: d(day), isOverdue: false,
                   appleSource: source)
    }
    private func layout(_ items: [AgendaItem], cap: Int = 6) -> [MonthWeek] {
        monthLayout(items: items, month: month, rowCapacity: cap)
    }
    private func allDay(_ id: String, _ start: String, end: String? = nil) -> Event {
        Event(id: id, title: id, start: d(start), end: end.map { d($0) }, isAllDay: true)
    }

    @Test func singleAllDayEventIsOneDayBar() {
        let e = allDay("a", "2026-11-04")
        let w = layout(rows(e, from: "2026-11-04", days: 1))
        #expect(w[0].bars.count == 1)
        let b = w[0].bars[0]
        #expect(b.startColumn == 3 && b.endColumn == 3 && b.lane == 0)
        #expect(!b.continuesBefore && !b.continuesAfter)
    }

    @Test func multiDayEventOneBarWithinWeek() {
        let e = allDay("a", "2026-11-03", end: "2026-11-05")
        let w = layout(rows(e, from: "2026-11-03", days: 3))
        #expect(w[0].bars.count == 1)
        #expect(w[0].bars[0].startColumn == 2 && w[0].bars[0].endColumn == 4 && w[0].bars[0].lane == 0)
    }

    @Test func multiDayCrossingWeekSplitsIntoTwoPieces() {
        let e = allDay("a", "2026-11-06", end: "2026-11-09")
        let w = layout(rows(e, from: "2026-11-06", days: 4))
        let first = w[0].bars[0], second = w[1].bars[0]
        #expect(first.startColumn == 5 && first.endColumn == 6 && first.continuesAfter && !first.continuesBefore)
        #expect(second.startColumn == 0 && second.endColumn == 1 && second.continuesBefore && !second.continuesAfter)
        #expect(first.title == second.title)
    }

    @Test func eventStartingBeforeGridIsClippedWithContinuesBefore() {
        // Grid starts Nov 1; the event began Oct 30 and ends Nov 2.
        let e = allDay("a", "2026-10-30", end: "2026-11-02")
        let w = layout(rows(e, from: "2026-11-01", days: 2))
        let b = w[0].bars[0]
        #expect(b.startColumn == 0 && b.endColumn == 1)
        #expect(b.continuesBefore && !b.continuesAfter)
    }

    @Test func dailyRepeatingAllDayEventStaysSeparateOneDayBars() {
        let e = allDay("a", "2026-11-01")
        let w = layout(rows(e, from: "2026-11-01", days: 7))
        #expect(w[0].bars.count == 7)
        #expect(w[0].bars.allSatisfy { $0.startColumn == $0.endColumn })
    }

    @Test func overlappingBarsGetDifferentLanes() {
        let a = allDay("a", "2026-11-02", end: "2026-11-04")
        let b = allDay("b", "2026-11-04", end: "2026-11-05")
        let w = layout(rows(a, from: "2026-11-02", days: 3) + rows(b, from: "2026-11-04", days: 2))
        let lanes = Dictionary(uniqueKeysWithValues: w[0].bars.map { ($0.title, $0.lane) })
        #expect(lanes["a"] == 0)
        #expect(lanes["b"] == 1)
    }

    @Test func holidayCalendarTitleMakesHolidayChipCaseInsensitive() {
        let e = allDay("a", "2026-11-04")
        let holiday = AppleSource(calendarID: "c", calendarTitle: "US HoliDays", colorHex: nil, isReminder: false)
        let plain = AppleSource(calendarID: "c", calendarTitle: "Work", colorHex: nil, isReminder: false)
        #expect(layout(rows(e, from: "2026-11-04", days: 1, source: holiday))[0].bars[0].isHoliday)
        #expect(!layout(rows(e, from: "2026-11-04", days: 1, source: plain))[0].bars[0].isHoliday)
    }

    @Test func timedEventAndReminderLinesInOrder() {
        let late = Event(id: "late", title: "Late", start: at("2026-11-04", 15))
        let early = Event(id: "early", title: "Early", start: at("2026-11-04", 9))
        let open2 = Reminder(id: "r2", title: "Open B", dueDate: at("2026-11-04", 11))
        let open1 = Reminder(id: "r1", title: "Open A", dueDate: at("2026-11-04", 8))
        let doneR = Reminder(id: "r3", title: "Done", dueDate: at("2026-11-04", 7), isCompleted: true)
        let items = [reminderRow(doneR, day: "2026-11-04"), reminderRow(open2, day: "2026-11-04"),
                     eventRow(late, day: "2026-11-04"), reminderRow(open1, day: "2026-11-04"),
                     eventRow(early, day: "2026-11-04")]
        let lines = layout(items)[0].lines[3]
        #expect(lines.map(\.title) == ["Early", "Late", "Open A", "Open B", "Done"])
        #expect(lines[0].kind == .timed(colorRGB: nil))
        #expect(lines[4].kind == .reminder(isCompleted: true, isRecurring: false))
    }

    @Test func recurringReminderLineFlagged() {
        let local = Reminder(id: "l", title: "Local", dueDate: at("2026-11-04", 9),
                             recurrence: RecurrenceRule(frequency: .weekly))
        let apple = Reminder(id: "a", title: "Apple", dueDate: at("2026-11-04", 10))
        let src = AppleSource(calendarID: "c", calendarTitle: "R", colorHex: nil, isReminder: true,
                              isRecurringSeries: true)
        let lines = layout([reminderRow(local, day: "2026-11-04"),
                            reminderRow(apple, day: "2026-11-04", source: src)])[0].lines[3]
        #expect(lines[0].kind == .reminder(isCompleted: false, isRecurring: true))
        #expect(lines[1].kind == .reminder(isCompleted: false, isRecurring: true))
    }

    @Test func overflowReplacesLastRowAndCountsAllHidden() {
        // Capacity 3: a bar (1 row) + four lines on Nov 4. Label takes the last row, so one line
        // shows and the other three are hidden. Other days stay at 0.
        let bar = allDay("bar", "2026-11-04")
        var items = rows(bar, from: "2026-11-04", days: 1)
        for k in 0..<4 {
            let r = Reminder(id: "r\(k)", title: "R\(k)", dueDate: at("2026-11-04", 8 + k))
            items.append(reminderRow(r, day: "2026-11-04"))
        }
        let w = layout(items, cap: 3)[0]
        #expect(w.lines[3].count == 1)
        #expect(w.overflow[3] == 3)
        #expect(w.overflow.enumerated().allSatisfy { $0.offset == 3 || $0.element == 0 })
        #expect(w.bars.count == 1)
    }

    @Test func barBeyondCapacityCountsInOverflowOfItsDays() {
        // Capacity 2, three stacked bars on Nov 4: lane 0 stays, lanes 1 and 2 are hidden.
        let items = ["a", "b", "c"].flatMap { rows(allDay($0, "2026-11-04"), from: "2026-11-04", days: 1) }
        let w = layout(items, cap: 2)[0]
        #expect(w.bars.count == 1)
        #expect(w.overflow[3] == 2)
        #expect(w.lines[3].isEmpty)
    }

    @Test func emptyMonthHasSevenEmptyColumnsPerWeek() {
        let w = layout([])
        #expect(w.count == 6)
        for week in w {
            #expect(week.bars.isEmpty)
            #expect(week.lines.count == 7 && week.lines.allSatisfy { $0.isEmpty })
            #expect(week.overflow == [Int](repeating: 0, count: 7))
        }
    }

    @Test func leapFebruaryAndFiveRowMonthProduceOneWeekPerGridRow() {
        for m in [YearMonth(year: 2028, month0: 1), YearMonth(year: 2026, month0: 1)] {
            let w = monthLayout(items: [], month: m, rowCapacity: 4)
            #expect(w.count == MonthGrid.days(for: m).count / 7)
            #expect(w.allSatisfy { $0.lines.count == 7 && $0.overflow.count == 7 })
        }
    }

    @Test func agendaRowsOutsideGridAreIgnored() {
        let e = allDay("a", "2026-06-10")
        let r = Reminder(id: "r", title: "R", dueDate: d("2027-03-01"))
        let w = layout(rows(e, from: "2026-06-10", days: 1) + [reminderRow(r, day: "2027-03-01")])
        #expect(w.allSatisfy { $0.bars.isEmpty && $0.lines.allSatisfy { $0.isEmpty } })
    }

    @Test func overdueReminderAppearsOnlyOnItsDisplayDay() {
        let r = Reminder(id: "r", title: "Late", dueDate: at("2026-11-02", 9))
        let item = AgendaItem(kind: .reminder(r), occurrence: at("2026-11-02", 9), displayDate: d("2026-11-10"),
                              isOverdue: true)
        let w = layout([item])
        #expect(w[1].lines[2].map(\.title) == ["Late"])
        #expect(w[0].lines.allSatisfy { $0.isEmpty })
    }

    @Test func keptBarInLabelRowCountsAsHiddenOnOverflowingDay() {
        // Capacity 3, bars A, B across the week (lanes 0, 1) and C on cols 0-1 (lane 2), plus one
        // line on col 0. Col 0 overflows (3 lanes + 1 line > 3): C and the line are hidden -> 2.
        // Col 1 holds exactly 3 rows, no overflow, so C stays in `bars` and col 1 counts 0.
        let a = allDay("a", "2026-11-01", end: "2026-11-07")
        let b = allDay("b", "2026-11-01", end: "2026-11-06")
        let c = allDay("c", "2026-11-01", end: "2026-11-02")
        let r = Reminder(id: "r", title: "R", dueDate: at("2026-11-01", 9))
        let items = rows(a, from: "2026-11-01", days: 7) + rows(b, from: "2026-11-01", days: 6)
            + rows(c, from: "2026-11-01", days: 2) + [reminderRow(r, day: "2026-11-01")]
        let w = layout(items, cap: 3)[0]
        #expect(w.bars.first { $0.title == "c" }?.lane == 2)
        #expect(w.overflow[0] == 2)
        #expect(w.lines[0].isEmpty)
        #expect(w.overflow[1] == 0)
    }

    @Test func rowCapacityOneHidesEverythingOnBusyDays() {
        let r1 = Reminder(id: "r1", title: "A", dueDate: at("2026-11-04", 9))
        let r2 = Reminder(id: "r2", title: "B", dueDate: at("2026-11-04", 10))
        let r3 = Reminder(id: "r3", title: "C", dueDate: at("2026-11-05", 10))
        let w = layout([reminderRow(r1, day: "2026-11-04"), reminderRow(r2, day: "2026-11-04"),
                        reminderRow(r3, day: "2026-11-05")], cap: 1)[0]
        #expect(w.lines[3].isEmpty && w.overflow[3] == 2)
        #expect(w.lines[4].count == 1 && w.overflow[4] == 0)
    }

    @Test func barLongerThanAWeekKeepsLinesInSecondWeek() {
        let e = allDay("a", "2026-11-05", end: "2026-11-12")
        let r = Reminder(id: "r", title: "R", dueDate: at("2026-11-10", 9))
        let w = layout(rows(e, from: "2026-11-05", days: 8) + [reminderRow(r, day: "2026-11-10")])
        #expect(w[0].bars.count == 1 && w[0].bars[0].continuesAfter)
        #expect(w[1].bars.count == 1 && w[1].bars[0].continuesBefore && !w[1].bars[0].continuesAfter)
        #expect(w[1].bars[0].endColumn == 4)
        #expect(w[1].lines[2].map(\.title) == ["R"])
    }

    @Test func lanesArePlacedLongestFirst() {
        // The shorter bar starts earlier but the longer one takes lane 0.
        let short = allDay("short", "2026-11-02", end: "2026-11-03")
        let long = allDay("long", "2026-11-03", end: "2026-11-06")
        let w = layout(rows(short, from: "2026-11-02", days: 2) + rows(long, from: "2026-11-03", days: 4))
        let lanes = Dictionary(uniqueKeysWithValues: w[0].bars.map { ($0.title, $0.lane) })
        #expect(lanes["long"] == 0 && lanes["short"] == 1)
    }

    // Known gap: a clipped RECURRING event (or an Apple series) has no known real start, so its
    // first grid day is taken as the chunk start and it does not report continuesBefore.
}
