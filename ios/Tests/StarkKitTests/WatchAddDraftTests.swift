import Foundation
import Testing
@testable import StarkKit

@Suite("WatchAddDraft")
struct WatchAddDraftTests {
    static let zones = ["Pacific/Honolulu", "America/New_York", "Asia/Tokyo"]

    static func calendar(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        c.locale = Locale(identifier: "en_US")
        return c
    }

    static func date(_ c: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Wednesday 2026-11-18, 09:30 local.
    static func now(_ c: Calendar) -> Date { date(c, 2026, 11, 18, 9, 30) }

    static func make(_ text: String, _ zone: String) -> WatchAddDraft? {
        let c = calendar(zone)
        return WatchAddDraft.make(dictation: text, now: now(c), calendar: c)
    }

    @Test("a dated phrase is a reminder unless it says event or appointment", arguments: zones)
    func datedPhraseIsAReminder(zone: String) throws {
        let c = Self.calendar(zone)
        let milk = try #require(Self.make("Buy milk today", zone))
        #expect(milk.kind == .reminder)
        #expect(milk.title == "Buy milk")
        #expect(milk.start == Self.date(c, 2026, 11, 18))
        #expect(milk.isAllDay)
        let call = try #require(Self.make("Call mom tomorrow at 5pm", zone))
        #expect(call.kind == .reminder)
        #expect(call.start == Self.date(c, 2026, 11, 19, 17, 0))
        #expect(!call.isAllDay)
        #expect(call.end == nil)
        let friday = try #require(Self.make("Buy milk Friday", zone))
        #expect(friday.title == "Buy milk")
        #expect(friday.start == Self.date(c, 2026, 11, 20))
    }

    @Test("saying event or appointment makes an event", arguments: zones)
    func eventWords(zone: String) throws {
        let c = Self.calendar(zone)
        let lunch = try #require(Self.make("Event lunch with Sarah at 1pm tomorrow", zone))
        #expect(lunch.kind == .event)
        #expect(lunch.title == "lunch with Sarah")
        let dentist = try #require(Self.make("Dentist appointment tomorrow at 2pm", zone))
        #expect(dentist.kind == .event)
        #expect(dentist.title == "Dentist appointment")
        #expect(dentist.start == Self.date(c, 2026, 11, 19, 14, 0))
        let undated = try #require(Self.make("New event team party", zone))
        #expect(undated.title == "team party")
        #expect(undated.start == Self.date(c, 2026, 11, 18))
        #expect(undated.isAllDay)
        #expect(undated.newEvent() != nil)
        #expect(undated.summary == "Today")
        let asked = try #require(Self.make("Remind me to book an appointment tomorrow", zone))
        #expect(asked.kind == .reminder)
        let events = try #require(Self.make("Plan events tomorrow", zone))
        #expect(events.kind == .reminder)
    }

    @Test("lunch tomorrow at one is a timed event with one hour", arguments: zones)
    func lunchTomorrowAtOneIsATimedEventWithOneHour(zone: String) throws {
        let c = Self.calendar(zone)
        let d = try #require(Self.make("Event Lunch with Sarah at 1pm tomorrow", zone))
        #expect(d.kind == .event)
        #expect(d.title == "Lunch with Sarah")
        #expect(d.start == Self.date(c, 2026, 11, 19, 13, 0))
        #expect(d.end == Self.date(c, 2026, 11, 19, 14, 0))
        #expect(!d.isAllDay)
        #expect(!d.summary.isEmpty)
        let e = try #require(d.newEvent())
        #expect(e.title == "Lunch with Sarah")
        #expect(e.start == d.start)
        #expect(e.end == d.end)
    }

    @Test("pay rent every month is a repeating reminder", arguments: zones)
    func payRentEveryMonthIsARepeatingReminder(zone: String) throws {
        let d = try #require(Self.make("Pay rent every month", zone))
        #expect(d.kind == .reminder)
        #expect(d.title == "Pay rent")
        #expect(d.recurrence != nil)
        #expect(d.start != nil)
        #expect(d.isAllDay)
        #expect(d.newReminder()?.recurrence == d.recurrence)
    }

    @Test("text with no date becomes a date-only reminder due today", arguments: zones)
    func textWithNoDateBecomesAReminderDueToday(zone: String) throws {
        let c = Self.calendar(zone)
        let d = try #require(Self.make("  Call mom ", zone))
        #expect(d.kind == .reminder)
        #expect(d.title == "Call mom")
        #expect(d.start == Self.date(c, 2026, 11, 18))
        #expect(d.isAllDay)
        #expect(d.end == nil)
        #expect(d.recurrence == nil)
        #expect(d.summary == "Reminder, Today")
    }

    @Test("empty and whitespace give no draft", arguments: zones)
    func emptyAndWhitespaceGiveNoDraft(zone: String) {
        #expect(Self.make("", zone) == nil)
        #expect(Self.make("   \n", zone) == nil)
    }

    @Test("new reminder carries title and due", arguments: zones)
    func newReminderCarriesTitleAndDue(zone: String) throws {
        let c = Self.calendar(zone)
        let d = try #require(Self.make("remind me to call mom at 5pm tomorrow", zone))
        #expect(d.kind == .reminder)
        let r = try #require(d.newReminder())
        #expect(r.title == "call mom")
        #expect(r.due == Self.date(c, 2026, 11, 19, 17, 0))
        #expect(r.dueHasTime)
        #expect(d.newEvent() == nil)
    }

    @Test("new event is nil for a reminder draft", arguments: zones)
    func newEventIsNilForAReminderDraft(zone: String) throws {
        let d = try #require(Self.make("Call mom", zone))
        #expect(d.newEvent() == nil)
        let r = try #require(d.newReminder())
        #expect(r.due == Self.date(Self.calendar(zone), 2026, 11, 18))
        #expect(!r.dueHasTime)
    }

    @Test("remind me to with no date is also due today", arguments: zones)
    func remindMeWithNoDateIsDueToday(zone: String) throws {
        let d = try #require(Self.make("Remind me to buy milk", zone))
        #expect(d.kind == .reminder)
        #expect(d.title == "buy milk")
        #expect(d.start == Self.date(Self.calendar(zone), 2026, 11, 18))
        #expect(d.isAllDay)
        #expect(d.summary == "Reminder, Today")
    }

    @Test("draft round trips through JSON", arguments: zones)
    func draftRoundTripsThroughJSON(zone: String) throws {
        let d = try #require(Self.make("Standup at 9am every weekday", zone))
        #expect(d.recurrence != nil)
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(WatchAddDraft.self, from: data)
        #expect(back == d)
    }
}
