import Foundation
import Testing
@testable import StarkKit

@Suite("QuickAddParser")
struct QuickAddParserTests {
    static let zones = ["Pacific/Honolulu", "America/New_York", "Asia/Tokyo"]

    static func calendar(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }

    static func date(_ c: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Wednesday 2026-11-18, 09:30 local.
    static func now(_ c: Calendar) -> Date { date(c, 2026, 11, 18, 9, 30) }

    static func parse(_ text: String, _ zone: String, now: Date? = nil) -> QuickAddSuggestion? {
        let c = calendar(zone)
        return QuickAddParser.parse(text, now: now ?? Self.now(c), calendar: c)
    }

    @Test("nothing recognised gives no suggestion", arguments: zones)
    func nothing(zone: String) {
        #expect(Self.parse("Call mom", zone) == nil)
        #expect(Self.parse("", zone) == nil)
    }

    @Test("only a date gives no suggestion (empty title)", arguments: zones)
    func onlyDate(zone: String) {
        #expect(Self.parse("tomorrow", zone) == nil)
        #expect(Self.parse("tomorrow at 1pm", zone) == nil)
    }

    @Test("lunch tomorrow at 1pm", arguments: zones)
    func lunch(zone: String) throws {
        let c = Self.calendar(zone)
        let s = try #require(Self.parse("Lunch with Sarah at 1pm tomorrow", zone))
        #expect(s.title == "Lunch with Sarah")
        #expect(s.start == Self.date(c, 2026, 11, 19, 13, 0))
        #expect(s.hasTime)
        #expect(s.recurrence == nil)
        #expect(s.kind == nil)
    }

    @Test("date without time is date-only at start of day", arguments: zones)
    func dateOnly(zone: String) throws {
        let c = Self.calendar(zone)
        let s = try #require(Self.parse("Dentist tomorrow", zone))
        #expect(s.title == "Dentist")
        #expect(s.start == Self.date(c, 2026, 11, 19))
        #expect(!s.hasTime)
    }

    @Test("monthly repeat without a date", arguments: zones)
    func monthly(zone: String) throws {
        let s = try #require(Self.parse("Pay rent every month", zone))
        #expect(s.title == "Pay rent")
        #expect(s.recurrence == RecurrenceRule(frequency: .monthly))
        #expect(s.start == nil)
        #expect(!s.hasTime)
    }

    @Test("weekly on two days at 6am", arguments: zones)
    func gym(zone: String) throws {
        let c = Self.calendar(zone)
        let s = try #require(Self.parse("Gym every Mon and Wed at 6am", zone))
        #expect(s.title == "Gym")
        #expect(s.recurrence == RecurrenceRule(frequency: .weekly, byDay: [.monday, .wednesday]))
        #expect(s.hasTime)
        // Wednesday 06:00 already passed at 09:30, so the first one is Monday 11/23.
        #expect(s.start == Self.date(c, 2026, 11, 23, 6, 0))
    }

    @Test("remind me to is a reminder", arguments: zones)
    func remind(zone: String) throws {
        let c = Self.calendar(zone)
        let s = try #require(Self.parse("Remind me to call the bank friday", zone))
        #expect(s.kind == .reminder)
        #expect(s.title == "call the bank")
        #expect(s.start == Self.date(c, 2026, 11, 20))
        #expect(!s.hasTime)
    }

    @Test("a kind prefix alone is a suggestion")
    func prefixOnly() throws {
        let s = try #require(Self.parse("todo: buy milk", "Asia/Tokyo"))
        #expect(s.kind == .reminder)
        #expect(s.title == "buy milk")
        #expect(s.start == nil)
    }

    @Test("date words inside longer words are not dates", arguments: zones)
    func longerWords(zone: String) {
        #expect(Self.parse("Saturnalia party", zone) == nil)
        #expect(Self.parse("Decide on mayo", zone) == nil)
        #expect(Self.parse("Sundae social", zone) == nil)
        #expect(Self.parse("Tomorrowland tickets", zone) == nil)
    }

    @Test("a lone may is a verb, not May", arguments: zones)
    func may(zone: String) {
        #expect(Self.parse("Ask if I may leave", zone) == nil)
        #expect(Self.parse("may I park here", zone) == nil)
    }

    @Test("may with a day number is May", arguments: zones)
    func mayDate(zone: String) throws {
        let c = Self.calendar(zone)
        let s = try #require(Self.parse("Conference May 5", zone))
        #expect(s.title == "Conference")
        #expect(s.start == Self.date(c, 2027, 5, 5))
    }

    @Test("month and day, with year inference", arguments: zones)
    func monthDay(zone: String) throws {
        let c = Self.calendar(zone)
        let a = try #require(Self.parse("Party on Dec 5th at 7:30pm", zone))
        #expect(a.title == "Party")
        #expect(a.start == Self.date(c, 2026, 12, 5, 19, 30))
        #expect(a.hasTime)
        let b = try #require(Self.parse("Taxes on 3/4", zone))
        #expect(b.start == Self.date(c, 2027, 3, 4))
        let d = try #require(Self.parse("Concert March 3 2028", zone))
        #expect(d.start == Self.date(c, 2028, 3, 3))
    }

    @Test("for 2 hours sets the end", arguments: zones)
    func duration(zone: String) throws {
        let c = Self.calendar(zone)
        let s = try #require(Self.parse("Workshop tomorrow at 2pm for 2 hours", zone))
        #expect(s.title == "Workshop")
        #expect(s.start == Self.date(c, 2026, 11, 19, 14, 0))
        #expect(s.end == Self.date(c, 2026, 11, 19, 16, 0))
        let m = try #require(Self.parse("Standup tomorrow 9am for 30 min", zone))
        #expect(m.end == Self.date(c, 2026, 11, 19, 9, 30))
    }

    @Test("every 2 weeks is interval 2", arguments: zones)
    func interval(zone: String) throws {
        let s = try #require(Self.parse("Review every 2 weeks", zone))
        #expect(s.title == "Review")
        #expect(s.recurrence == RecurrenceRule(frequency: .weekly, interval: 2))
    }

    @Test("other repeat phrases")
    func repeats() throws {
        let z = "America/New_York"
        #expect(try #require(Self.parse("Vitamins daily", z)).recurrence == RecurrenceRule(frequency: .daily))
        #expect(try #require(Self.parse("Vitamins every day", z)).recurrence == RecurrenceRule(frequency: .daily))
        #expect(try #require(Self.parse("Water plants weekly", z)).recurrence == RecurrenceRule(frequency: .weekly))
        #expect(try #require(Self.parse("Renew domain every year", z)).recurrence == RecurrenceRule(frequency: .yearly))
        #expect(try #require(Self.parse("Mom's birthday annually", z)).recurrence == RecurrenceRule(frequency: .yearly))
        #expect(try #require(Self.parse("Pay rent every 3 months", z)).recurrence == RecurrenceRule(frequency: .monthly, interval: 3))
        #expect(try #require(Self.parse("Trash every tuesday", z)).recurrence == RecurrenceRule(frequency: .weekly, byDay: [.tuesday]))
    }

    @Test("noon, 24 hour times and in N days", arguments: zones)
    func times(zone: String) throws {
        let c = Self.calendar(zone)
        let a = try #require(Self.parse("Lunch noon tomorrow", zone))
        #expect(a.start == Self.date(c, 2026, 11, 19, 12, 0))
        #expect(a.hasTime)
        let b = try #require(Self.parse("Train today at 17:45", zone))
        #expect(b.start == Self.date(c, 2026, 11, 18, 17, 45))
        let d = try #require(Self.parse("Follow up in 3 days", zone))
        #expect(d.start == Self.date(c, 2026, 11, 21))
        #expect(!d.hasTime)
    }

    @Test("a time earlier today rolls to tomorrow when no date is given", arguments: zones)
    func timeRolls(zone: String) throws {
        let c = Self.calendar(zone)
        let late = try #require(Self.parse("Call dad at 5pm", zone))
        #expect(late.start == Self.date(c, 2026, 11, 18, 17, 0))
        let early = try #require(Self.parse("Call dad at 8am", zone))
        #expect(early.start == Self.date(c, 2026, 11, 19, 8, 0))
    }

    @Test("day boundary: tomorrow at 23:30 local stays on the local next day", arguments: zones)
    func dayBoundary(zone: String) throws {
        let c = Self.calendar(zone)
        let now = Self.date(c, 2026, 11, 18, 23, 30)
        let s = try #require(Self.parse("Pack tomorrow", zone, now: now))
        #expect(s.start == Self.date(c, 2026, 11, 19))
    }

    @Test("DST: wall-clock times survive a change")
    func dst() throws {
        let c = Self.calendar("America/New_York")
        let fall = try #require(Self.parse("Brunch tomorrow at 1pm", "America/New_York",
                                           now: Self.date(c, 2026, 10, 31, 10, 0)))
        #expect(c.dateComponents([.month, .day, .hour], from: fall.start!) == DateComponents(month: 11, day: 1, hour: 13))
        let spring = try #require(Self.parse("Walk tomorrow at 9am", "America/New_York",
                                             now: Self.date(c, 2026, 3, 7, 10, 0)))
        #expect(c.dateComponents([.month, .day, .hour], from: spring.start!) == DateComponents(month: 3, day: 8, hour: 9))
        let week = try #require(Self.parse("Check in 7 days", "America/New_York",
                                           now: Self.date(c, 2026, 10, 28)))
        #expect(week.start == Self.date(c, 2026, 11, 4))
    }

    @Test("summary text")
    func summary() throws {
        let s = try #require(Self.parse("Lunch with Sarah at 1pm tomorrow", "America/New_York"))
        #expect(s.summary == "Tomorrow at 1:00 PM")
        let r = try #require(Self.parse("Gym every Mon and Wed at 6am", "America/New_York"))
        #expect(r.summary == "Mon, Nov 23 at 6:00 AM, repeats every week on Monday, Wednesday")
        let m = try #require(Self.parse("Pay rent every month", "America/New_York"))
        #expect(m.summary == "Repeats every month")
    }

    @Test("false positives from the review")
    func falsePositives() throws {
        let z = "America/New_York"
        let c = Self.calendar(z)
        for text in ["Task force meeting", "Todo list app", "Read John 3:16", "Buy 1/2 gallon milk",
                     "Pick up 20 may people", "Tomorrow's meeting", "Reminder about rent"] {
            #expect(Self.parse(text, z) == nil, "\(text)")
        }
        let r = try #require(Self.parse("task: file taxes", z))
        #expect(r.kind == .reminder && r.title == "file taxes")
        let r2 = try #require(Self.parse("Reminder to pay rent", z))
        #expect(r2.kind == .reminder && r2.title == "pay rent")
        let by = try #require(Self.parse("Report due by 1/2", z))
        #expect(by.start == Self.date(c, 2027, 1, 2))
        let yr = try #require(Self.parse("Report 1/2/2028", z))
        #expect(yr.start == Self.date(c, 2028, 1, 2))
        let on = try #require(Self.parse("Party on may 20", z))
        #expect(on.start == Self.date(c, 2027, 5, 20))
        let bad = try #require(Self.parse("Call at 13pm tomorrow", z))
        #expect(bad.title == "Call at 13pm")
        #expect(bad.start == Self.date(c, 2026, 11, 19))
        #expect(!bad.hasTime)
        let feb = try #require(Self.parse("Feb 30 dentist tomorrow", z))
        #expect(feb.title == "Feb 30 dentist")
        #expect(feb.start == Self.date(c, 2026, 11, 19))
        let at = try #require(Self.parse("Coffee @5pm tomorrow", z))
        #expect(at.title == "Coffee")
        #expect(at.start == Self.date(c, 2026, 11, 19, 17, 0))
    }
}
