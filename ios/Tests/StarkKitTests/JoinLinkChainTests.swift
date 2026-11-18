import Foundation
import Testing
@testable import StarkKit

/// The whole path a join link and an event time zone take: EventKit-shaped snapshot -> the owner's
/// calendar selection -> the agenda merge / Search -> what the row and detail read.
@Suite struct JoinLinkChainTests {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ d: Int, _ h: Int) -> Date {
        Self.cal.date(from: DateComponents(year: 2026, month: 6, day: d, hour: h))!
    }

    private let work = AppleCalendarInfo(id: "work", title: "Work", accountName: "iCloud", colorHex: nil, isReminderList: false)

    private func snapshot(url: String? = "https://zoom.us/j/42", notes: String? = nil, allDay: Bool = false,
                          zone: String? = "Asia/Tokyo", detect: Bool = true) -> AppleSnapshot {
        let event = AppleCalendarEvent(id: "e1", title: "Standup", notes: notes, location: nil, url: url,
                                       start: at(10, 0), end: at(10, 1), isAllDay: allDay, calendar: work,
                                       timeZoneID: zone, joinLink: detect ? ConferenceLinkDetector.detect(url: url, location: nil, notes: notes) : nil)
        return AppleSnapshot(events: [event], reminders: [])
    }

    private func merged(_ snap: AppleSnapshot) -> [AgendaItem] {
        let filtered = AppleSelection(excludedIDs: ["other"]).filtered(snap)
        return mergeAppleItems([], snapshot: filtered, in: at(1, 0)...at(30, 0), today: at(5, 0), calendar: Self.cal)
    }

    @Test func filteredKeepsTheNewFields() {
        let filtered = AppleSelection().filtered(snapshot())
        #expect(filtered.events[0].timeZoneID == "Asia/Tokyo")
        #expect(filtered.events[0].url == "https://zoom.us/j/42")
    }

    @Test func agendaRowCarriesLinkAndZone() {
        let rows = merged(snapshot())
        #expect(rows.count == 1)
        #expect(rows[0].appleSource?.conferenceLink?.provider == .zoom)
        #expect(rows[0].appleSource?.timeZoneID == "Asia/Tokyo")
        #expect(rows[0].conferenceLink?.title == "Join Zoom")
        #expect(rows[0].showsJoinGlyph)
        let card = rows[0].timeZoneCard(phoneZone: TimeZone(identifier: "America/New_York")!, locale: Locale(identifier: "en_US"))
        #expect(card?.zoneName == "Tokyo")
        #expect(card?.eventRange == "Wed, Jun 10, 9:00 AM–10:00 AM GMT+9")
        #expect(card?.yourRange == "8:00 PM–9:00 PM")
    }

    /// The link is detected once, where the event is read (EventKitProvider.map); merges and Search
    /// only carry it, so an event built without one shows none even if its URL is a Zoom link.
    @Test func mergeAndSearchCarryTheStoredLinkInsteadOfDetectingAgain() {
        let snap = snapshot(detect: false)
        #expect(merged(snap)[0].conferenceLink == nil)
        let results = SearchResults.find(events: [], reminders: [], apple: snap, query: "standup", today: at(5, 0))
        #expect(results[0].conferenceLink == nil)
        #expect(!results[0].showsJoinGlyph)
    }

    @Test func filteredKeepsTheStoredLink() {
        #expect(AppleSelection().filtered(snapshot()).events[0].joinLink?.provider == .zoom)
    }

    @Test func linkFromNotesWhenUrlIsNotAConferenceLink() {
        let rows = merged(snapshot(url: "https://example.com/agenda", notes: "Join https://meet.google.com/abc-defg-hij."))
        #expect(rows[0].conferenceLink?.provider == .googleMeet)
    }

    @Test func allDayEventShowsNoGlyphAndNoCard() {
        let rows = merged(snapshot(allDay: true))
        #expect(rows[0].conferenceLink != nil)
        #expect(!rows[0].showsJoinGlyph)
        #expect(rows[0].timeZoneCard(phoneZone: TimeZone(identifier: "America/New_York")!, locale: Locale(identifier: "en_US")) == nil)
    }

    @Test func plainEventHasNeither() {
        let rows = merged(snapshot(url: nil, zone: nil))
        #expect(rows[0].conferenceLink == nil)
        #expect(!rows[0].showsJoinGlyph)
        #expect(rows[0].timeZoneCard(phoneZone: TimeZone(identifier: "America/New_York")!, locale: Locale(identifier: "en_US")) == nil)
    }

    @Test func reminderRowsNeverShowTheGlyph() {
        let list = AppleCalendarInfo(id: "l", title: "Home", accountName: "iCloud", colorHex: nil, isReminderList: true)
        let reminder = AppleReminder(id: "r1", title: "Call https://zoom.us/j/1", notes: nil, due: at(10, 9), dueHasTime: true,
                                     isCompleted: false, completedAt: nil, priority: nil, calendar: list,
                                     url: "https://zoom.us/j/1")
        let rows = mergeAppleItems([], snapshot: AppleSnapshot(events: [], reminders: [reminder]),
                                   in: at(1, 0)...at(30, 0), today: at(5, 0), calendar: Self.cal)
        #expect(rows.count == 1)
        #expect(!rows[0].showsJoinGlyph)
        #expect(rows[0].conferenceLink == nil)
    }

    @Test func searchResultCarriesLinkAndZone() {
        let results = SearchResults.find(events: [], reminders: [], apple: snapshot(), query: "standup", today: at(5, 0))
        #expect(results.count == 1)
        #expect(results[0].conferenceLink?.provider == .zoom)
        #expect(results[0].appleSource?.timeZoneID == "Asia/Tokyo")
    }
}
