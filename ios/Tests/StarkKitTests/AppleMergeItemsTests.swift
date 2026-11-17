import Foundation
import Testing
@testable import StarkKit

extension AppleMergeTests {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ d: Int, _ h: Int = 0, _ m: Int = 0, month: Int = 6) -> Date {
        Self.cal.date(from: DateComponents(year: 2026, month: month, day: d, hour: h, minute: m))!
    }

    private var info: AppleCalendarInfo { AppleCalendarInfo(id: "cal1", title: "Work", accountName: "iCloud", colorHex: "#FF0000", isReminderList: false) }
    private var today: Date { date(15, 10) }
    private var range: ClosedRange<Date> { date(1)...date(30, 23, 59) }

    private func event(_ id: String = "e1", start: Date, end: Date?, allDay: Bool = false) -> AppleCalendarEvent {
        AppleCalendarEvent(id: id, title: "Evt", notes: "n", location: "L", url: "https://x.y", start: start, end: end, isAllDay: allDay, calendar: info)
    }

    private func reminder(_ id: String = "r1", due: Date?, hasTime: Bool = true, done: Bool = false) -> AppleReminder {
        AppleReminder(id: id, title: "Rem", notes: nil, due: due, dueHasTime: hasTime, isCompleted: done,
                      completedAt: done ? due : nil, priority: 1, calendar: info)
    }

    private func merge(_ items: [AgendaItem] = [], events: [AppleCalendarEvent] = [], reminders: [AppleReminder] = []) -> [AgendaItem] {
        mergeAppleItems(items, snapshot: AppleSnapshot(events: events, reminders: reminders), in: range, today: today, calendar: Self.cal)
    }

    @Test func timedEventKeepsStartAndEnd() {
        let out = merge(events: [event(start: date(10, 9), end: date(10, 10))])
        #expect(out.count == 1)
        guard case .event(let e) = out[0].kind else { Issue.record("not event"); return }
        #expect(e.id == "apple-e1")
        #expect(e.start == date(10, 9) && e.end == date(10, 10))
        #expect(e.recurrence == nil && e.location == "L" && e.url == "https://x.y")
        #expect(out[0].occurrence == date(10, 9) && out[0].displayDate == date(10, 9))
        #expect(!out[0].isOverdue)
        #expect(out[0].appleSource == AppleSource(calendarID: "cal1", calendarTitle: "Work", colorHex: "#FF0000", isReminder: false))
    }

    @Test func idNeverCollidesWithStarkUUID() {
        let out = merge(events: [event(start: date(10, 9), end: nil)], reminders: [reminder(due: date(12, 9))])
        #expect(out.count == 2)
        #expect(out.allSatisfy { $0.id.hasPrefix("apple-") })
    }

    @Test func eventOutsideRangeDropped() {
        let out = merge(events: [event(start: date(1, 9, month: 8), end: date(1, 10, month: 8))])
        #expect(out.isEmpty)
    }

    @Test func threeDayAllDayEventGivesThreeRows() {
        let out = merge(events: [event(start: date(10), end: date(12), allDay: true)])
        #expect(out.map(\.displayDate) == [date(10), date(11), date(12)])
        #expect(out.map(\.occurrence) == [date(10), date(11), date(12)])
    }

    @Test func eventEndingAtMidnightDoesNotSpillToNextDay() {
        let out = merge(events: [event(start: date(10, 22), end: date(11))])
        #expect(out.count == 1)
        #expect(out[0].displayDate == date(10, 22))
    }

    @Test func reminderOnItsDueDay() {
        let out = merge(reminders: [reminder(due: date(20, 9))])
        #expect(out.count == 1)
        guard case .reminder(let r) = out[0].kind else { Issue.record("not reminder"); return }
        #expect(r.id == "apple-r1" && r.dueDate == date(20, 9) && r.recurrence == nil && r.priority == 1)
        #expect(out[0].displayDate == date(20, 9) && !out[0].isOverdue)
        #expect(out[0].appleSource?.isReminder == true)
    }

    @Test func dateOnlyReminderHasNoTimeOfDay() {
        let out = merge(reminders: [reminder(due: date(20, 13, 37), hasTime: false)])
        guard case .reminder(let r) = out[0].kind else { Issue.record("not reminder"); return }
        #expect(r.dueDate == date(20))
        #expect(out[0].occurrence == date(20))
    }

    @Test func overdueReminderPinnedToToday() {
        let out = merge(reminders: [reminder(due: date(10, 9))])
        #expect(out.count == 1)
        #expect(out[0].isOverdue)
        #expect(out[0].displayDate == Self.cal.startOfDay(for: today))
        #expect(out[0].occurrence == date(10, 9))
    }

    @Test(arguments: [169, 400, 89, 91, 90])
    func openReminderOfAnyAgeIsOverdueToday(daysAgo: Int) {
        let due = Self.cal.date(byAdding: .day, value: -daysAgo, to: Self.cal.startOfDay(for: today))!
        let out = merge(reminders: [reminder(due: due, hasTime: false)])
        #expect(out.count == 1)
        guard let row = out.first else { return }
        #expect(row.isOverdue)
        #expect(row.displayDate == Self.cal.startOfDay(for: today))
        #expect(row.occurrence == due)
    }

    @Test func veryOldOverdueRowRendersCappedLabel() {
        let due = Self.cal.date(byAdding: .day, value: -400, to: Self.cal.startOfDay(for: today))!
        let out = merge(reminders: [reminder(due: due, hasTime: false)])
        #expect(out.first?.daysOverdue(today: today, calendar: Self.cal) == 400)
        #expect(OverdueLabel.text(daysOverdue: 400) == "90+ days overdue")
    }

    @Test func oldCompletedReminderNotShown() {
        let due = Self.cal.date(byAdding: .day, value: -400, to: today)!
        #expect(merge(reminders: [reminder(due: due, done: true)]).isEmpty)
    }

    @Test func reminderDueTodayAndFutureAsBefore() {
        let out = merge(reminders: [reminder("t", due: date(15, 18)), reminder("f", due: date(20, 9))])
        #expect(out.count == 2)
        #expect(out.allSatisfy { !$0.isOverdue })
        #expect(out.map(\.displayDate).contains(date(15, 18)))
    }

    @Test func completedReminderOnDueDay() {
        let out = merge(reminders: [reminder(due: date(10, 9), done: true)])
        #expect(out.count == 1)
        #expect(out[0].isCompleted && !out[0].isOverdue)
        #expect(out[0].displayDate == date(10, 9))
    }

    @Test func undatedReminderNotShown() {
        #expect(merge(reminders: [reminder(due: nil)]).isEmpty)
    }

    @Test func starkItemsUnchangedAndOrdered() {
        let stark = Event(id: "AAAA", title: "Mine", start: date(10, 8), end: date(10, 8, 30))
        let base = [AgendaItem(kind: .event(stark), occurrence: stark.start, displayDate: stark.start, isOverdue: false)]
        let out = merge(base, events: [event(start: date(10, 7), end: date(10, 7, 30))])
        #expect(out.count == 2)
        #expect(out[0].id.hasPrefix("apple-"))
        #expect(out[1] == base[0])
    }

    // MARK: DST, timezone and boundary cases

    private static let ny: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func nyDate(_ month: Int, _ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        Self.ny.date(from: DateComponents(year: 2026, month: month, day: d, hour: h, minute: m))!
    }

    private func nyMerge(events: [AppleCalendarEvent] = [], reminders: [AppleReminder] = [], today: Date) -> [AgendaItem] {
        let range = nyDate(3, 1)...nyDate(3, 31, 23, 59)
        return mergeAppleItems([], snapshot: AppleSnapshot(events: events, reminders: reminders), in: range, today: today, calendar: Self.ny)
    }

    @Test func dstSpringForwardTimedEventAndDateOnlyReminderLandOnTheRightDay() {
        // 2026-03-08: clocks jump 02:00 -> 03:00 in New York.
        let evt = event(start: nyDate(3, 8, 3, 30), end: nyDate(3, 8, 4, 30))
        let rem = reminder(due: nyDate(3, 8, 13, 37), hasTime: false)
        let out = nyMerge(events: [evt], reminders: [rem], today: nyDate(3, 8, 8))
        #expect(out.count == 2)
        #expect(out.allSatisfy { Self.ny.component(.day, from: $0.displayDate) == 8 })
        let r = out.first { $0.appleSource?.isReminder == true }
        #expect(r?.occurrence == nyDate(3, 8))
        #expect(r?.isOverdue == false)
    }

    @Test func dstAllDayEventSpanningSpringForwardGivesOneRowPerDay() {
        let out = nyMerge(events: [event(start: nyDate(3, 7), end: nyDate(3, 9), allDay: true)], today: nyDate(3, 7, 8))
        #expect(out.count == 3)
        #expect(out.map { Self.ny.component(.day, from: $0.displayDate) } == [7, 8, 9])
        #expect(out.allSatisfy { Self.ny.startOfDay(for: $0.displayDate) == $0.displayDate })
    }

    @Test func sameInstantLandsOnDifferentDaysInDifferentCalendars() {
        // 2026-06-10 02:00 UTC is still June 9 in New York (UTC-4).
        let instant = date(10, 2)
        let wide = date(1, month: 5)...date(30, 23, 59, month: 7)
        let snap = AppleSnapshot(events: [event(start: instant, end: nil)], reminders: [])
        let utc = mergeAppleItems([], snapshot: snap, in: wide, today: date(15, 10), calendar: Self.cal)
        let ny = mergeAppleItems([], snapshot: snap, in: wide, today: date(15, 10), calendar: Self.ny)
        #expect(Self.cal.component(.day, from: utc[0].displayDate) == 10)
        #expect(Self.ny.component(.day, from: ny[0].displayDate) == 9)
        // Date-only reminder stored at that instant: start-of-day differs per calendar.
        let remSnap = AppleSnapshot(events: [], reminders: [reminder(due: instant, hasTime: false)])
        let ru = mergeAppleItems([], snapshot: remSnap, in: wide, today: date(15, 10), calendar: Self.cal)
        let rn = mergeAppleItems([], snapshot: remSnap, in: wide, today: date(15, 10), calendar: Self.ny)
        #expect(ru[0].occurrence == date(10))
        #expect(rn[0].occurrence == Self.ny.date(from: DateComponents(year: 2026, month: 6, day: 9))!)
    }

    @Test func reminderDueEarlierTodayIsNotOverdue() {
        let out = merge(reminders: [reminder(due: date(15, 8))])
        #expect(out.count == 1)
        #expect(!out[0].isOverdue)
        #expect(out[0].displayDate == date(15, 8))
    }

    @Test func reminderDueAfterRangeDropped() {
        #expect(merge(reminders: [reminder(due: date(5, 9, month: 7))]).isEmpty)
    }

    @Test func completedReminderOutsideRangeDropped() {
        #expect(merge(reminders: [reminder("a", due: date(20, 9, month: 5), done: true),
                                  reminder("b", due: date(5, 9, month: 7), done: true)]).isEmpty)
    }

    @Test func timedEventRunningMidnightToMidnightGivesOneRow() {
        let out = merge(events: [event(start: date(10), end: date(11))])
        #expect(out.count == 1)
        #expect(out[0].displayDate == date(10))
    }

    /// A daily 22:00-02:00 series (night shifts): EventKit returns one occurrence per day, all
    /// with the same series id. Monday's spill-over row onto Tuesday would get Tuesday 22:00 as
    /// its occurrence, the same row id as Tuesday's own occurrence; only one row per day is kept,
    /// and the kept row is the occurrence's own.
    @Test func overnightDailySeriesGivesOneRowPerDayWithUniqueIds() {
        let shifts = (10...13).map { d in event("night", start: date(d, 22), end: date(d + 1, 2)) }
        let out = merge(events: shifts)
        #expect(Set(out.map(\.id)).count == out.count)
        // Own rows on the 10th to the 13th, plus the last shift's spill-over onto the 14th.
        #expect(out.map(\.displayDate) == [date(10, 22), date(11, 22), date(12, 22), date(13, 22), date(14, 22)])
        for d in 10...13 {
            let row = out.first { Self.cal.isDate($0.displayDate, inSameDayAs: date(d)) }
            guard case .event(let e)? = row?.kind else { Issue.record("no row on \(d)"); continue }
            #expect(e.start == date(d, 22))
            #expect(row?.occurrence == date(d, 22))
        }
    }

    @Test func overnightDailySeriesCountsOncePerDayInDensity() {
        let shifts = (10...13).map { d in event("night", start: date(d, 22), end: date(d + 1, 2)) }
        let d = dayDensity(events: [], reminders: [], month: YearMonth(year: 2026, month0: 5), today: today,
                           calendar: Self.cal, apple: AppleSnapshot(events: shifts, reminders: []))
        // The helper calendar is #FF0000, so each day also carries that colour (the old colourless equality had to change).
        for day in 10...14 { #expect(d[day] == DayDensity(tasks: 0, events: 1, eventColors: [0xFF0000])) }
    }

    private var listInfo: AppleCalendarInfo { AppleCalendarInfo(id: "list", title: "Home", accountName: "iCloud", colorHex: nil, isReminderList: true) }

    private func reminder(url: String?) -> AppleReminder {
        AppleReminder(id: "r", title: "Pay", notes: nil, due: date(20, 9), dueHasTime: true, isCompleted: false,
                      completedAt: nil, priority: nil, calendar: listInfo, url: url)
    }

    @Test func reminderURLCarriedToTheRow() {
        let row = merge(reminders: [reminder(url: "https://bank.example/pay")]).first
        #expect(row?.appleSource?.url == "https://bank.example/pay")
        #expect(row.flatMap(appleItemURL) == "https://bank.example/pay")
    }

    @Test func reminderWithoutURLHasNone() {
        let row = merge(reminders: [reminder(url: nil)]).first
        #expect(row != nil)
        #expect(row?.appleSource?.url == nil)
        #expect(row.flatMap(appleItemURL) == nil)
    }

    @Test func eventURLComesFromTheEvent() {
        let row = merge(events: [event(start: date(20, 9), end: date(20, 10))]).first
        #expect(row.flatMap(appleItemURL) == "https://x.y")
    }

    @Test func emptyReminderURLIsNone() {
        let row = merge(reminders: [reminder(url: "")]).first
        #expect(row != nil)
        #expect(row.flatMap(appleItemURL) == nil)
    }
}
