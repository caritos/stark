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

    @Test func reminderOlderThanLookbackNotShown() {
        let old = Self.cal.date(byAdding: .day, value: -(AgendaWindow.overdueLookbackDays + 5), to: today)!
        let out = merge(reminders: [reminder(due: old)])
        #expect(out.isEmpty)
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
}
