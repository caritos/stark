import Foundation
import Testing
@testable import StarkKit

@Suite struct BirthdayFetchGateTests {
    private func event(_ id: String, birthdays: Bool, contactID: String?) -> AppleCalendarEvent {
        let info = AppleCalendarInfo(id: "cal", title: birthdays ? "Birthdays" : "Work", accountName: "iCloud",
                                     colorHex: nil, isReminderList: false, isBirthdayCalendar: birthdays)
        return AppleCalendarEvent(id: id, title: "T", notes: nil, location: nil, url: nil,
                                  start: Date(timeIntervalSince1970: 0), end: nil, isAllDay: true,
                                  calendar: info, birthdayContactID: contactID)
    }

    @Test func noBirthdayEventsNeedNoLookup() {
        #expect(BirthYear.contactIDsNeeded(in: []).isEmpty)
        #expect(BirthYear.contactIDsNeeded(in: [event("a", birthdays: false, contactID: "c1")]).isEmpty)
    }

    @Test func idsOfBirthdayEvents() {
        let events = [event("a", birthdays: true, contactID: "c1"), event("b", birthdays: true, contactID: "c2"),
                      event("c", birthdays: true, contactID: "c1")]
        #expect(BirthYear.contactIDsNeeded(in: events) == ["c1", "c2"])
    }

    @Test func birthdayEventWithoutContactIsIgnored() {
        #expect(BirthYear.contactIDsNeeded(in: [event("a", birthdays: true, contactID: nil)]).isEmpty)
    }
}
