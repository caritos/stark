import Foundation
import Testing
@testable import StarkKit

@Suite struct EventTimeZoneCardTests {
    private let us = Locale(identifier: "en_US")
    private func zone(_ id: String) -> TimeZone { TimeZone(identifier: id)! }

    /// A UTC instant.
    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone("UTC")
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func make(start: Date, end: Date?, allDay: Bool = false, id: String?, phone: String,
                      locale: Locale? = nil) -> EventTimeZoneCard? {
        EventTimeZoneCardMaker.make(start: start, end: end, isAllDay: allDay, timeZoneID: id,
                                    phoneZone: zone(phone), locale: locale ?? us)
    }

    @Test func tokyoEventSeenFromLosAngeles() {
        // 9:00 AM GMT+9 = 00:00 UTC; Los Angeles is UTC-8 in January: 4:00 PM the day before.
        let card = make(start: utc(2026, 1, 15, 0), end: utc(2026, 1, 15, 1), id: "Asia/Tokyo", phone: "America/Los_Angeles")
        #expect(card?.zoneName == "Tokyo")
        // Tokyo is already on Thursday Jan 15 while Los Angeles is still on the 14th.
        #expect(card?.eventRange == "Thu, Jan 15, 9:00 AM–10:00 AM GMT+9")
        #expect(card?.yourRange == "4:00 PM–5:00 PM")
        #expect(card?.summary == "Tokyo · Thu, Jan 15, 9:00 AM–10:00 AM GMT+9 (your time 4:00 PM–5:00 PM)")
    }

    @Test func sameZoneHasNoCard() {
        #expect(make(start: utc(2026, 1, 15, 0), end: utc(2026, 1, 15, 1), id: "Asia/Tokyo", phone: "Asia/Tokyo") == nil)
    }

    @Test func differentIDsWithTheSameOffsetHaveNoCard() {
        // London and Dublin share an offset in winter (and summer); Reykjavik is UTC all year.
        #expect(make(start: utc(2026, 1, 15, 12), end: nil, id: "Europe/London", phone: "Europe/Dublin") == nil)
        #expect(make(start: utc(2026, 1, 15, 12), end: nil, id: "Atlantic/Reykjavik", phone: "Europe/London") == nil)
    }

    @Test func floatingAllDayAndUnknownZoneHaveNoCard() {
        #expect(make(start: utc(2026, 1, 15, 0), end: nil, id: nil, phone: "America/New_York") == nil)
        #expect(make(start: utc(2026, 1, 15, 0), end: nil, allDay: true, id: "Asia/Tokyo", phone: "America/New_York") == nil)
        #expect(make(start: utc(2026, 1, 15, 0), end: nil, id: "Mars/Olympus_Mons", phone: "America/New_York") == nil)
        #expect(make(start: utc(2026, 1, 15, 0), end: nil, id: "", phone: "America/New_York") == nil)
    }

    @Test func missingEndShowsOnlyTheStart() {
        let card = make(start: utc(2026, 1, 15, 0), end: nil, id: "Asia/Tokyo", phone: "America/New_York")
        #expect(card?.eventRange == "Thu, Jan 15, 9:00 AM GMT+9")
        #expect(card?.yourRange == "7:00 PM")
        let same = make(start: utc(2026, 1, 15, 0), end: utc(2026, 1, 15, 0), id: "Asia/Tokyo", phone: "America/New_York")
        #expect(same?.eventRange == "Thu, Jan 15, 9:00 AM GMT+9")
    }

    @Test func overnightInTheOtherZone() {
        // 11:00 PM to 1:00 AM in Tokyo = 14:00-16:00 UTC.
        let card = make(start: utc(2026, 1, 15, 14), end: utc(2026, 1, 15, 16), id: "Asia/Tokyo", phone: "America/New_York")
        #expect(card?.eventRange == "11:00 PM–Fri, Jan 16, 1:00 AM GMT+9")
        #expect(card?.yourRange == "9:00 AM–11:00 AM")
    }

    @Test func halfHourZone() {
        // Kolkata is UTC+5:30: 10:30 AM IST = 05:00 UTC; New York in January is UTC-5.
        let card = make(start: utc(2026, 1, 15, 5), end: utc(2026, 1, 15, 6), id: "Asia/Kolkata", phone: "America/New_York")
        #expect(card?.zoneName == "Kolkata")
        #expect(card?.eventRange == "10:30 AM–11:30 AM GMT+5:30")
        #expect(card?.yourRange == "12:00 AM–1:00 AM")
    }

    @Test func phoneInKiritimati() {
        let card = make(start: utc(2026, 1, 15, 0), end: utc(2026, 1, 15, 1), id: "Asia/Tokyo", phone: "Pacific/Kiritimati")
        #expect(card?.yourRange == "2:00 PM–3:00 PM")
    }

    @Test func underscoresInCityNames() {
        let card = make(start: utc(2026, 1, 15, 15), end: nil, id: "America/Los_Angeles", phone: "Asia/Tokyo")
        #expect(card?.zoneName == "Los Angeles")
        #expect(card?.eventRange.hasSuffix("PST") == true)
    }

    @Test func dstDifferenceCountsAtTheStartInstant() {
        // New York vs Sydney: 15 hours apart in January... and in July 14 hours; always different.
        // London vs New York on 2026-03-20 (US already on DST, UK not): 4 hours, not 5.
        let card = make(start: utc(2026, 3, 20, 13), end: utc(2026, 3, 20, 14), id: "Europe/London", phone: "America/New_York")
        #expect(card?.eventRange == "1:00 PM–2:00 PM GMT")
        #expect(card?.yourRange == "9:00 AM–10:00 AM")
        // Same two zones a few weeks later both on DST: still different, 5 hours apart.
        let later = make(start: utc(2026, 5, 20, 13), end: nil, id: "Europe/London", phone: "America/New_York")
        #expect(later?.eventRange == "2:00 PM GMT+1")
        #expect(later?.yourRange == "9:00 AM")
    }

    @Test func twentyFourHourLocale() {
        let card = make(start: utc(2026, 1, 15, 0), end: utc(2026, 1, 15, 1), id: "Asia/Tokyo", phone: "Europe/Berlin",
                        locale: Locale(identifier: "de_DE"))
        #expect(card?.eventRange.hasPrefix("09:00–10:00") == true)
        #expect(card?.yourRange == "01:00–02:00")
    }

    @Test func dayIsShownWhenTheEventsDayDiffersFromThePhones() {
        // 12:00 PM in New York on Wed Nov 18 is 2:00 AM Thu Nov 19 in Tokyo.
        let card = make(start: utc(2026, 11, 18, 17), end: utc(2026, 11, 18, 18), id: "Asia/Tokyo", phone: "America/New_York")
        #expect(card?.eventRange == "Thu, Nov 19, 2:00 AM–3:00 AM GMT+9")
        #expect(card?.yourRange == "12:00 PM–1:00 PM")
        #expect(card?.summary == "Tokyo · Thu, Nov 19, 2:00 AM–3:00 AM GMT+9 (your time 12:00 PM–1:00 PM)")
    }

    @Test func dayIsShownWhenOnlyThePhoneIsOnAnotherDay() {
        // 9:00 AM Wed in Honolulu is 9:00 AM Thu in Kiritimati: the clock times look identical.
        let card = make(start: utc(2026, 11, 18, 19), end: utc(2026, 11, 18, 20), id: "Pacific/Honolulu", phone: "Pacific/Kiritimati")
        #expect(card?.zoneName == "Honolulu")
        #expect(card?.eventRange == "Wed, Nov 18, 9:00 AM–10:00 AM HST")
        #expect(card?.yourRange == "9:00 AM–10:00 AM")
        #expect(card?.summary == "Honolulu · Wed, Nov 18, 9:00 AM–10:00 AM HST (your time 9:00 AM–10:00 AM)")
    }

    @Test func multiDayEventNamesTheEndDayInBothZones() {
        // Sat Jan 3 9:00 AM in Tokyo to Sun Jan 4 9:00 AM; Friday evening to Saturday evening in New York.
        let card = make(start: utc(2026, 1, 3, 0), end: utc(2026, 1, 4, 0), id: "Asia/Tokyo", phone: "America/New_York")
        #expect(card?.eventRange == "Sat, Jan 3, 9:00 AM–Sun, Jan 4, 9:00 AM GMT+9")
        #expect(card?.yourRange == "7:00 PM–Sat, Jan 3, 7:00 PM")
    }

    @Test func multiDayEventOnTheSameStartDayHasNoStartPrefix() {
        // Kolkata is on the same day as Tokyo at this instant.
        let card = make(start: utc(2026, 1, 3, 0), end: utc(2026, 1, 4, 0), id: "Asia/Tokyo", phone: "Asia/Kolkata")
        #expect(card?.eventRange == "9:00 AM–Sun, Jan 4, 9:00 AM GMT+9")
        #expect(card?.yourRange == "5:30 AM–Sun, Jan 4, 5:30 AM")
    }

    @Test func etcZonesUseTheAbbreviationAsTheName() {
        // Etc/GMT-9 is UTC+9; a city line would read "GMT-9" and contradict "GMT+9".
        let card = make(start: utc(2026, 1, 15, 0), end: nil, id: "Etc/GMT-9", phone: "America/New_York")
        #expect(card?.zoneName == "GMT+9")
        #expect(card?.eventRange.hasSuffix("GMT+9") == true)
    }
}
