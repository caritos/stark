import Foundation
import Testing
@testable import StarkKit

@Suite("AppleDensitySearch")
struct AppleDensitySearchTests {
    private let cal = Calendar(identifier: .gregorian)

    private func date(_ month: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: d, hour: h))!
    }

    private var info: AppleCalendarInfo { AppleCalendarInfo(id: "c", title: "Work", accountName: "iCloud", colorHex: nil, isReminderList: false) }
    private var today: Date { date(6, 15, 10) }

    private func appleEvent(_ title: String = "Dentist", location: String? = nil, start: Date) -> AppleCalendarEvent {
        AppleCalendarEvent(id: "e-\(title)", title: title, notes: nil, location: location, url: nil,
                           start: start, end: start.addingTimeInterval(3600), isAllDay: false, calendar: info)
    }

    private func appleReminder(_ title: String = "Call", notes: String? = nil, due: Date?) -> AppleReminder {
        AppleReminder(id: "r-\(title)", title: title, notes: notes, due: due, dueHasTime: true, isCompleted: false,
                      completedAt: nil, priority: nil, calendar: info)
    }

    @Test func gridDensityCountsAppleEventsAndReminders() {
        let snap = AppleSnapshot(events: [appleEvent(start: date(6, 10, 9))], reminders: [appleReminder(due: date(6, 20, 9))])
        let d = gridDensity(events: [], reminders: [], month: YearMonth(year: 2026, month0: 5), today: today, calendar: cal, apple: snap)
        #expect(d["2026-06-10"] == DayDensity(tasks: 0, events: 1))
        #expect(d["2026-06-20"] == DayDensity(tasks: 1, events: 0))
    }

    @Test func dayDensityCountsApple() {
        let snap = AppleSnapshot(events: [appleEvent(start: date(6, 10, 9))], reminders: [])
        let d = dayDensity(events: [], reminders: [], month: YearMonth(year: 2026, month0: 5), today: today, calendar: cal, apple: snap)
        #expect(d[10] == DayDensity(tasks: 0, events: 1))
    }

    @Test func yearDensityCountsApple() {
        let snap = AppleSnapshot(events: [appleEvent(start: date(3, 4, 9))], reminders: [appleReminder(due: date(11, 20, 9))])
        let d = yearDensity(events: [], reminders: [], year: 2026, today: today, calendar: cal, apple: snap)
        #expect(d["2026-03-04"]?.events == 1)
        #expect(d["2026-11-20"]?.tasks == 1)
    }

    @Test func existingCallsUnchangedWithEmptySnapshot() {
        let stark = Event(id: "AAAA", title: "Mine", start: date(6, 10, 9), end: date(6, 10, 10))
        let month = YearMonth(year: 2026, month0: 5)
        let without = gridDensity(events: [stark], reminders: [], month: month, today: today, calendar: cal)
        let with = gridDensity(events: [stark], reminders: [], month: month, today: today, calendar: cal,
                               apple: AppleSnapshot(events: [], reminders: []))
        #expect(without == with)
        #expect(without["2026-06-10"] == DayDensity(tasks: 0, events: 1))
    }

    @Test func searchFindsAppleEventByTitle() {
        let snap = AppleSnapshot(events: [appleEvent("Dentist", start: date(6, 20, 9)), appleEvent("Gym", start: date(6, 21, 9))], reminders: [])
        let out = SearchResults.find(events: [], reminders: [], apple: snap, query: "dENt", today: today)
        #expect(out.count == 1)
        #expect(out[0].appleSource?.isReminder == false)
        #expect(out[0].displayDate == date(6, 20, 9))
    }

    @Test func searchFindsAppleEventByLocation() {
        let snap = AppleSnapshot(events: [appleEvent("Lunch", location: "Cafe Roma", start: date(6, 20, 12))], reminders: [])
        #expect(SearchResults.find(events: [], reminders: [], apple: snap, query: "roma", today: today).count == 1)
    }

    @Test func searchFindsAppleReminderByNotes() {
        let snap = AppleSnapshot(events: [], reminders: [appleReminder("Call", notes: "about the Invoice", due: date(6, 18, 9))])
        let out = SearchResults.find(events: [], reminders: [], apple: snap, query: "invoice", today: today)
        #expect(out.count == 1)
        #expect(out[0].appleSource?.isReminder == true)
        #expect(out[0].displayDate == date(6, 18, 9))
    }

    @Test func searchResultsSortedNewestFirstWithStarkItems() {
        let stark = Event(id: "AAAA", title: "Dentist mine", start: date(6, 19, 9), end: nil)
        let snap = AppleSnapshot(events: [appleEvent("Dentist A", start: date(6, 20, 9)), appleEvent("Dentist B", start: date(6, 10, 9))], reminders: [])
        let out = SearchResults.find(events: [stark], reminders: [], apple: snap, query: "dentist", today: today)
        #expect(out.map(\.displayDate) == [date(6, 20, 9), date(6, 19, 9), date(6, 10, 9)])
        #expect(out.map { $0.appleSource != nil } == [true, false, true])
    }
}
