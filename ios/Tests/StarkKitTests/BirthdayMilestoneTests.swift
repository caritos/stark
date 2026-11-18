import Foundation
import Testing
@testable import StarkKit

@Suite struct BirthdayMilestoneTests {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ d: Int, month: Int = 6) -> Date {
        Self.cal.date(from: DateComponents(year: 2026, month: month, day: d))!
    }

    private var range: ClosedRange<Date> { date(1)...date(30) }

    private func merge(birthdays: Bool, contactID: String? = "c1", years: [String: Int],
                       notes: String? = nil, title: String = "Ann's Birthday") -> [AgendaItem] {
        let info = AppleCalendarInfo(id: "cal", title: birthdays ? "Birthdays" : "Work", accountName: "iCloud",
                                     colorHex: nil, isReminderList: false, isWritable: !birthdays,
                                     isBirthdayCalendar: birthdays)
        let event = AppleCalendarEvent(id: "e1", title: title, notes: notes, location: nil, url: nil,
                                       start: date(10), end: nil, isAllDay: true, calendar: info,
                                       birthdayContactID: contactID)
        let snap = AppleSnapshot(events: [event], reminders: [], birthYears: years)
        return mergeAppleItems([], snapshot: snap, in: range, today: date(15), calendar: Self.cal)
    }

    @Test func yearFromComponents() {
        #expect(BirthYear.year(from: DateComponents(year: 1990, month: 5, day: 3)) == 1990)
        #expect(BirthYear.year(from: DateComponents(month: 5, day: 3)) == nil)
        #expect(BirthYear.year(from: DateComponents(year: 1604, month: 5, day: 3)) == nil)
        #expect(BirthYear.year(from: nil) == nil)
    }

    @Test func birthdayCalendarGivesAge() {
        let m = merge(birthdays: true, years: ["c1": 1990])[0].milestone
        #expect(m?.kind == .birthday)
        #expect(m?.years == 36)
        #expect(m?.note == "Turns 36")
    }

    @Test func noBirthYearGivesCakeOnly() {
        let m = merge(birthdays: true, years: [:])[0].milestone
        #expect(m?.kind == .birthday)
        #expect(m?.years == nil)
    }

    @Test func birthYearEqualToOccurrenceYearGivesNoAge() {
        let m = merge(birthdays: true, years: ["c1": 2026])[0].milestone
        #expect(m?.kind == .birthday)
        #expect(m?.years == nil)
    }

    @Test func normalCalendarHasNoMilestone() {
        #expect(merge(birthdays: false, contactID: nil, years: [:], title: "Lunch")[0].milestone == nil)
    }

    @Test func taggedNormalEventStillBirthday() {
        let m = merge(birthdays: false, contactID: nil, years: [:], title: "Bob %birthday")[0].milestone
        #expect(m?.kind == .birthday)
        #expect(m?.years == nil)
    }

    @Test func oldSnapshotInitStillCompiles() {
        let s = AppleSnapshot(events: [], reminders: [])
        #expect(s.birthYears.isEmpty)
        #expect(AppleSnapshot.empty.birthYears.isEmpty)
    }
}
