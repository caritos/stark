import Foundation
import Testing
@testable import StarkKit

@Suite("QuickAddParser")
struct QuickAddParserTests {
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
        let s = try #require(Self.parse("Remind me to call the bank on friday", zone))
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
        #expect(try #require(Self.parse("Review weekly at 3pm", z)).recurrence == RecurrenceRule(frequency: .weekly))
    }

    @Test("a repeat with set days and no date starts on the next matching day", arguments: zones)
    func weekdayRepeatStart(zone: String) throws {
        let c = Self.calendar(zone)
        let trash = try #require(Self.parse("Trash every tuesday", zone))
        #expect(trash.start == Self.date(c, 2026, 11, 24))
        #expect(!trash.hasTime)
        // Today is Wednesday and matches: date-only start today.
        let gym = try #require(Self.parse("Gym every Mon and Wed", zone))
        #expect(gym.start == Self.date(c, 2026, 11, 18))
        #expect(!gym.hasTime)
        #expect(try #require(Self.parse("Pay rent every month", zone)).start == nil)
    }

    @Test("a non-Gregorian calendar never leaks in", arguments: [Calendar.Identifier.buddhist, .hebrew, .japanese])
    func otherCalendars(id: Calendar.Identifier) throws {
        let g = Self.calendar("America/New_York")
        var other = Calendar(identifier: id)
        other.timeZone = g.timeZone
        other.locale = Locale(identifier: "en_US")
        let s = try #require(QuickAddParser.parse("Concert March 3 2028 at 7pm", now: Self.now(g), calendar: other))
        #expect(s.start == Self.date(g, 2028, 3, 3, 19, 0))
        #expect(s.summary == "Fri, Mar 3, 2028 at 7:00 PM")
        let t = try #require(QuickAddParser.parse("Lunch tomorrow", now: Self.now(g), calendar: other))
        #expect(t.start == Self.date(g, 2026, 11, 19))
        #expect(t.summary == "Tomorrow")
    }

    @Test("ordinary words are not repeats, days or times", arguments: zones)
    func wordFalsePositives(zone: String) {
        for text in ["Weekly report", "Daily standup notes", "Friday Night Lights", "Good Friday", "Sunday roast",
                     "Midnight Express", "Today show", "Monthly budget review"] {
            #expect(Self.parse(text, zone) == nil, "\(text)")
        }
    }

    @Test("the same words still work with a cue", arguments: zones)
    func wordsWithCue(zone: String) throws {
        let c = Self.calendar(zone)
        let a = try #require(Self.parse("Call dad today", zone))
        #expect(a.title == "Call dad" && a.start == Self.date(c, 2026, 11, 18))
        let b = try #require(Self.parse("Meet on friday", zone))
        #expect(b.start == Self.date(c, 2026, 11, 20))
        let d = try #require(Self.parse("Ship by next monday", zone))
        #expect(d.title == "Ship" && d.start == Self.date(c, 2026, 11, 23))
        let e = try #require(Self.parse("Party at midnight", zone))
        #expect(e.title == "Party" && e.hasTime && e.start == Self.date(c, 2026, 11, 19, 0, 0))
        let f = try #require(Self.parse("Standup monthly", zone))
        #expect(f.recurrence == RecurrenceRule(frequency: .monthly))
    }

    @Test("a rejected date token leaves the rest of the text alone", arguments: zones)
    func rejectedDate(zone: String) throws {
        #expect(Self.parse("Flight 11/20 at 6am", zone) == nil)
        let s = try #require(Self.parse("Remind me to buy 1/2 gallon at 6am", zone))
        #expect(s.kind == .reminder)
        #expect(s.title == "buy 1/2 gallon at 6am")
        #expect(s.start == nil)
    }

    @Test("in N minutes rounds up to a quarter hour and other words still parse", arguments: zones)
    func relativeTimes(zone: String) throws {
        let c = Self.calendar(zone)
        let a = try #require(Self.parse("Call in 100 minutes", zone))
        #expect(a.title == "Call")
        #expect(a.start == Self.date(c, 2026, 11, 18, 11, 15))
        #expect(a.hasTime)
        let b = try #require(Self.parse("Call in 90 minutes", zone))
        #expect(b.start == Self.date(c, 2026, 11, 18, 11, 0))
        let d = try #require(Self.parse("Check in 3 hours tomorrow", zone))
        #expect(d.title == "Check")
        #expect(d.start == Self.date(c, 2026, 11, 19))
        #expect(!d.hasTime)
    }

    @Test("summary names a reminder and follows the 12 or 24 hour setting")
    func summaries() throws {
        let z = "America/New_York"
        let a = try #require(Self.parse("Remind me to call the bank on friday", z))
        #expect(a.summary == "Reminder, Fri, Nov 20")
        let b = try #require(Self.parse("Remind me to pay rent every month", z))
        #expect(b.summary == "Reminder, repeats every month")
        let c = Self.calendar(z)
        var gb = c
        gb.locale = Locale(identifier: "en_GB")
        let t = try #require(QuickAddParser.parse("Lunch at 1pm tomorrow", now: Self.now(c), calendar: gb))
        #expect(t.summary == "Tomorrow at 13:00")
    }

    @Test("form values: timed event")
    func formTimed() throws {
        let c = Self.calendar("America/New_York")
        let s = try #require(Self.parse("Workshop tomorrow at 2pm for 2 hours", "America/New_York"))
        let current = Self.date(c, 2026, 11, 18, 10, 0)
        let v = s.formValues(currentStart: current)
        #expect(v.title == "Workshop")
        #expect(v.allDay == false)
        #expect(v.start == s.start)
        // The Starts picker's onChange adds (start - current) to the end, so it lands on `end`.
        #expect(v.endForPicker!.addingTimeInterval(s.start!.timeIntervalSince(current)) == s.end)
        let d = try #require(Self.parse("Lunch at 1pm tomorrow", "America/New_York")).formValues(currentStart: current)
        #expect(d.endForPicker!.addingTimeInterval(d.start!.timeIntervalSince(current)) == d.start!.addingTimeInterval(3600))
    }

    @Test("form values: all day, reminder and nothing to set")
    func formOther() throws {
        let c = Self.calendar("America/New_York")
        let current = Self.date(c, 2026, 11, 18, 10, 0)
        let a = try #require(Self.parse("Dentist tomorrow", "America/New_York")).formValues(currentStart: current)
        #expect(a.allDay == true && a.kind == nil)
        let r = try #require(Self.parse("Remind me to pay rent every month", "America/New_York")).formValues(currentStart: current)
        #expect(r.kind == .reminder && r.start == nil && r.allDay == nil && r.endForPicker == nil)
        #expect(r.recurrence == RecurrenceRule(frequency: .monthly))
    }

    @Test("noon, 24 hour times and in N days", arguments: zones)
    func times(zone: String) throws {
        let c = Self.calendar(zone)
        let a = try #require(Self.parse("Lunch at noon tomorrow", zone))
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

    // MARK: - Second round

    @Test("time ranges", arguments: zones)
    func ranges(zone: String) throws {
        let c = Self.calendar(zone)
        let lunch = try #require(Self.parse("Lunch tomorrow 1-2pm", zone))
        #expect(lunch.title == "Lunch")
        #expect(lunch.start == Self.date(c, 2026, 11, 19, 13, 0))
        #expect(lunch.end == Self.date(c, 2026, 11, 19, 14, 0))
        #expect(lunch.hasTime)
        #expect(lunch.summary == "Tomorrow, 1:00 PM to 2:00 PM")
        let meet = try #require(Self.parse("Meeting tomorrow 11-1pm", zone))
        #expect(meet.start == Self.date(c, 2026, 11, 19, 11, 0))
        #expect(meet.end == Self.date(c, 2026, 11, 19, 13, 0))
        let cls = try #require(Self.parse("Class tomorrow 9am-10:30am", zone))
        #expect(cls.title == "Class")
        #expect(cls.start == Self.date(c, 2026, 11, 19, 9, 0))
        #expect(cls.end == Self.date(c, 2026, 11, 19, 10, 30))
        let words = try #require(Self.parse("Sync tomorrow from 1pm to 2pm", zone))
        #expect(words.title == "Sync")
        #expect(words.start == Self.date(c, 2026, 11, 19, 13, 0))
        #expect(words.end == Self.date(c, 2026, 11, 19, 14, 0))
        let to = try #require(Self.parse("Sync tomorrow 1 to 2pm", zone))
        #expect(to.end == Self.date(c, 2026, 11, 19, 14, 0))
        let until = try #require(Self.parse("Sync tomorrow 9am until 10:30am", zone))
        #expect(until.end == Self.date(c, 2026, 11, 19, 10, 30))
        let h24 = try #require(Self.parse("Review tomorrow 13:00-14:30", zone))
        #expect(h24.start == Self.date(c, 2026, 11, 19, 13, 0))
        #expect(h24.end == Self.date(c, 2026, 11, 19, 14, 30))
        let noDay = try #require(Self.parse("Standup 10-10:30am", zone))
        // 10:00 today has passed at 09:30? No: 10:00 is ahead, so today.
        #expect(noDay.start == Self.date(c, 2026, 11, 18, 10, 0))
        #expect(noDay.end == Self.date(c, 2026, 11, 18, 10, 30))
        let both = try #require(Self.parse("Dinner on friday 7-9pm for 2 hours", zone))
        #expect(both.title == "Dinner")
        #expect(both.start == Self.date(c, 2026, 11, 20, 19, 0))
        #expect(both.end == Self.date(c, 2026, 11, 20, 21, 0))
    }

    @Test("things that are not ranges", arguments: zones)
    func notRanges(zone: String) throws {
        let c = Self.calendar(zone)
        for text in ["Call 3-4", "Chapter 3-4", "Read pages 3-4", "Meet 3 to 4", "John 3:16-18"] {
            #expect(Self.parse(text, zone) == nil, "\(text)")
        }
        // A refused range leaves its whole token in the title and picks no time out of it.
        let flight = try #require(Self.parse("Flight tomorrow 6pm-5pm", zone))
        #expect(flight.end == nil)
        #expect(flight.title == "Flight 6pm-5pm")
        #expect(!flight.hasTime)
        #expect(flight.start == Self.date(c, 2026, 11, 19))
        let bad = try #require(Self.parse("Call tomorrow 13pm-14pm", zone))
        #expect(bad.end == nil)
        #expect(bad.title == "Call 13pm-14pm")
        #expect(!bad.hasTime)
        let score = try #require(Self.parse("Score tomorrow 3-2pm", zone))
        #expect(score.title == "Score 3-2pm")
        #expect(!score.hasTime && score.end == nil)
        #expect(Self.parse("Read John 11:25-12:30", zone) == nil)
        #expect(Self.parse("Party Dec 5-6", zone) == nil)
        #expect(Self.parse("Sync tomorrow 1 and 2pm", zone)?.end == nil)
        let tomorrow = try #require(Self.parse("Chapter 3-4 tomorrow", zone))
        #expect(tomorrow.title == "Chapter 3-4")
        #expect(!tomorrow.hasTime)
    }

    @Test("this and next weekday on a Wednesday", arguments: zones)
    func nextWeekdayWednesday(zone: String) throws {
        let c = Self.calendar(zone)
        #expect(try #require(Self.parse("Dentist this friday", zone)).start == Self.date(c, 2026, 11, 20))
        #expect(try #require(Self.parse("Dentist next friday", zone)).start == Self.date(c, 2026, 11, 27))
        #expect(try #require(Self.parse("Dentist this wednesday", zone)).start == Self.date(c, 2026, 11, 18))
        #expect(try #require(Self.parse("Dentist next wednesday", zone)).start == Self.date(c, 2026, 11, 25))
        #expect(try #require(Self.parse("Dentist next monday", zone)).start == Self.date(c, 2026, 11, 23))
        #expect(try #require(Self.parse("Dentist on friday", zone)).start == Self.date(c, 2026, 11, 20))
        #expect(try #require(Self.parse("Dentist on wednesday", zone)).start == Self.date(c, 2026, 11, 25))
        let t = try #require(Self.parse("Dentist next friday at 3pm", zone))
        #expect(t.title == "Dentist")
        #expect(t.start == Self.date(c, 2026, 11, 27, 15, 0))
    }

    @Test("this and next weekday on a Friday and a Sunday", arguments: zones)
    func nextWeekdayOtherDays(zone: String) throws {
        let c = Self.calendar(zone)
        let friday = Self.date(c, 2026, 11, 20, 9, 30)
        #expect(try #require(Self.parse("Dentist this friday", zone, now: friday)).start == Self.date(c, 2026, 11, 20))
        #expect(try #require(Self.parse("Dentist next friday", zone, now: friday)).start == Self.date(c, 2026, 11, 27))
        #expect(try #require(Self.parse("Dentist on friday", zone, now: friday)).start == Self.date(c, 2026, 11, 27))
        // Sunday-first weeks (en_US): on Sunday 11/22 the next week starts a week later.
        let sunday = Self.date(c, 2026, 11, 22, 9, 30)
        #expect(try #require(Self.parse("Dentist this friday", zone, now: sunday)).start == Self.date(c, 2026, 11, 27))
        #expect(try #require(Self.parse("Dentist next friday", zone, now: sunday)).start == Self.date(c, 2026, 12, 4))
        #expect(try #require(Self.parse("Dentist next monday", zone, now: sunday)).start == Self.date(c, 2026, 11, 30))
        #expect(try #require(Self.parse("Dentist next sunday", zone, now: sunday)).start == Self.date(c, 2026, 11, 29))
        // Saturday 11/21: next sunday is tomorrow (the new week starts Sunday).
        let saturday = Self.date(c, 2026, 11, 21, 9, 30)
        #expect(try #require(Self.parse("Dentist next sunday", zone, now: saturday)).start == Self.date(c, 2026, 11, 22))
        #expect(try #require(Self.parse("Dentist next friday", zone, now: saturday)).start == Self.date(c, 2026, 11, 27))
        // Monday 11/23: next monday is a week away.
        let monday = Self.date(c, 2026, 11, 23, 9, 30)
        #expect(try #require(Self.parse("Dentist next monday", zone, now: monday)).start == Self.date(c, 2026, 11, 30))
    }

    @Test("next weekday follows the calendar's first weekday (Monday-first)", arguments: zones)
    func nextWeekdayMondayFirst(zone: String) throws {
        var c = Self.calendar(zone)
        c.firstWeekday = 2
        func start(_ text: String, _ now: Date) throws -> Date? {
            try #require(QuickAddParser.parse(text, now: now, calendar: c)).start
        }
        let sunday = Self.date(c, 2026, 11, 22, 9, 30)
        #expect(try start("Dentist next friday", sunday) == Self.date(c, 2026, 11, 27))
        #expect(try start("Dentist next monday", sunday) == Self.date(c, 2026, 11, 23))
        let saturday = Self.date(c, 2026, 11, 21, 9, 30)
        #expect(try start("Dentist next sunday", saturday) == Self.date(c, 2026, 11, 29))
        #expect(try start("Dentist next monday", saturday) == Self.date(c, 2026, 11, 23))
        let wednesday = Self.date(c, 2026, 11, 18, 9, 30)
        #expect(try start("Dentist next friday", wednesday) == Self.date(c, 2026, 11, 27))
        #expect(try start("Dentist next monday", wednesday) == Self.date(c, 2026, 11, 23))
        #expect(try start("Dentist this friday", wednesday) == Self.date(c, 2026, 11, 20))
    }

    @Test("next weekday across the DST change")
    func nextWeekdayDST() throws {
        let c = Self.calendar("America/New_York")
        // Wednesday 2026-10-28; clocks fall back on Sunday 11/1.
        let now = Self.date(c, 2026, 10, 28, 9, 30)
        let s = try #require(Self.parse("Dentist next friday at 3pm", "America/New_York", now: now))
        #expect(s.start == Self.date(c, 2026, 11, 6, 15, 0))
        let t = try #require(Self.parse("Dentist this sunday", "America/New_York", now: now))
        #expect(t.start == Self.date(c, 2026, 11, 1))
    }

    @Test("every weekday and every weekend", arguments: zones)
    func weekdayRepeats(zone: String) throws {
        let c = Self.calendar(zone)
        let stand = try #require(Self.parse("Standup every weekday at 9am", zone))
        #expect(stand.title == "Standup")
        #expect(stand.recurrence == RecurrenceRule(frequency: .weekly,
                                                   byDay: [.monday, .tuesday, .wednesday, .thursday, .friday]))
        // Wednesday 9:00 has passed at 9:30: the next weekday is Thursday.
        #expect(stand.start == Self.date(c, 2026, 11, 19, 9, 0))
        #expect(stand.hasTime)
        let trash = try #require(Self.parse("Trash every weekend", zone))
        #expect(trash.title == "Trash")
        #expect(trash.recurrence == RecurrenceRule(frequency: .weekly, byDay: [.saturday, .sunday]))
        #expect(trash.start == Self.date(c, 2026, 11, 21))
        #expect(!trash.hasTime)
        let plural = try #require(Self.parse("Gym every weekdays", zone))
        #expect(plural.recurrence?.byDay?.count == 5)
        for text in ["Weekdays only", "Open weekdays 9am", "Weekend plans"] {
            #expect(Self.parse(text, zone)?.recurrence == nil, "\(text)")
        }
    }

    @Test("a range works under other calendars and next friday too", arguments: [Calendar.Identifier.buddhist, .hebrew])
    func rangeOtherCalendars(id: Calendar.Identifier) throws {
        let g = Self.calendar("America/New_York")
        var other = Calendar(identifier: id)
        other.timeZone = g.timeZone
        other.locale = Locale(identifier: "en_US")
        let s = try #require(QuickAddParser.parse("Lunch tomorrow 1-2pm", now: Self.now(g), calendar: other))
        #expect(s.start == Self.date(g, 2026, 11, 19, 13, 0))
        #expect(s.end == Self.date(g, 2026, 11, 19, 14, 0))
        let n = try #require(QuickAddParser.parse("Dentist next friday", now: Self.now(g), calendar: other))
        #expect(n.start == Self.date(g, 2026, 11, 27))
    }

    @Test("the row is hidden while the title is the one Apply produced")
    func hideRule() {
        #expect(!QuickAddSuggestion.shouldOffer(title: "Lunch", appliedTitle: "Lunch"))
        #expect(QuickAddSuggestion.shouldOffer(title: "Lunch x", appliedTitle: "Lunch"))
        #expect(QuickAddSuggestion.shouldOffer(title: "Lunch", appliedTitle: nil))
        #expect(QuickAddSuggestion.shouldOffer(title: "Dinner tomorrow 7-9pm", appliedTitle: "Lunch"))
    }

    // MARK: - Review fixes

    @Test("overnight ranges end on the next day", arguments: zones)
    func overnight(zone: String) throws {
        let c = Self.calendar(zone)
        let party = try #require(Self.parse("Party tomorrow 11pm-1am", zone))
        #expect(party.title == "Party")
        #expect(party.start == Self.date(c, 2026, 11, 19, 23, 0))
        #expect(party.end == Self.date(c, 2026, 11, 20, 1, 0))
        let shift = try #require(Self.parse("Shift tomorrow 10pm-6am", zone))
        #expect(shift.start == Self.date(c, 2026, 11, 19, 22, 0))
        #expect(shift.end == Self.date(c, 2026, 11, 20, 6, 0))
        let thing = try #require(Self.parse("Thing tomorrow 11-12am", zone))
        #expect(thing.title != "Thing 11")
        #expect(thing.title == "Thing" || thing.title == "Thing 11-12am")
        // Longer than 16 hours is not a range.
        let flight = try #require(Self.parse("Flight tomorrow 6pm-5pm", zone))
        #expect(flight.end == nil && flight.title == "Flight 6pm-5pm")
    }

    @Test("a day number before a range keeps the date", arguments: zones)
    func monthDayBeforeRange(zone: String) throws {
        let c = Self.calendar(zone)
        let s = try #require(Self.parse("Party Dec 5-6pm", zone))
        #expect(s.title == "Party")
        #expect(s.start == Self.date(c, 2026, 12, 5, 18, 0))
    }

    @Test("ranges on a DST gap day never end at the start")
    func dstGapRange() throws {
        let c = Self.calendar("America/New_York")
        let now = Self.date(c, 2027, 3, 10, 9, 30)
        let s = try #require(Self.parse("Class 3/14/2027 2:30am-3:30am", "America/New_York", now: now))
        if let start = s.start, let end = s.end { #expect(end > start) }
    }

    @Test("a reminder suggestion shows no end")
    func reminderNoEnd() throws {
        let s = try #require(Self.parse("Remind me to call tomorrow 1-2pm", "America/New_York"))
        #expect(s.kind == .reminder)
        #expect(s.end == nil)
        #expect(s.summary == "Reminder, Tomorrow at 1:00 PM")
    }

    @Test("between X and Y, til, and 24 hour ranges needing evidence", arguments: zones)
    func moreRangeWords(zone: String) throws {
        let c = Self.calendar(zone)
        let b = try #require(Self.parse("Sync tomorrow between 1 and 2pm", zone))
        #expect(b.title == "Sync")
        #expect(b.start == Self.date(c, 2026, 11, 19, 13, 0))
        #expect(b.end == Self.date(c, 2026, 11, 19, 14, 0))
        let t = try #require(Self.parse("Sync tomorrow 1pm til 2pm", zone))
        #expect(t.end == Self.date(c, 2026, 11, 19, 14, 0))
        let z = try #require(Self.parse("Review tomorrow 09:00-10:30", zone))
        #expect(z.start == Self.date(c, 2026, 11, 19, 9, 0))
        #expect(z.end == Self.date(c, 2026, 11, 19, 10, 30))
        let at = try #require(Self.parse("Review tomorrow from 11:25 to 12:30", zone))
        #expect(at.end == Self.date(c, 2026, 11, 19, 12, 30))
    }

    @Test("a repeat's start aligns to its days", arguments: zones)
    func repeatStartAligns(zone: String) throws {
        let c = Self.calendar(zone)
        let friday = Self.date(c, 2026, 11, 20, 9, 30)
        let a = try #require(Self.parse("Standup every weekday tomorrow at 9am", zone, now: friday))
        #expect(a.start == Self.date(c, 2026, 11, 23, 9, 0))
        let wed = try #require(Self.parse("Trash every weekend tomorrow", zone))
        #expect(wed.start == Self.date(c, 2026, 11, 21))
        let thursday = Self.date(c, 2026, 11, 19, 9, 30)
        let keep = try #require(Self.parse("Standup every weekday tomorrow at 9am", zone, now: thursday))
        #expect(keep.start == Self.date(c, 2026, 11, 20, 9, 0))
    }

    @Test("a bare weekday ends a reminder phrase", arguments: zones)
    func reminderBareWeekday(zone: String) throws {
        let c = Self.calendar(zone)
        let r = try #require(Self.parse("Remind me to call the bank Friday", zone))
        #expect(r.kind == .reminder)
        #expect(r.title == "call the bank")
        #expect(r.start == Self.date(c, 2026, 11, 20))
        #expect(!r.hasTime)
        let n = try #require(Self.parse("Remind me to buy Friday Night Lights tickets", zone))
        #expect(n.start == nil)
        #expect(n.title == "buy Friday Night Lights tickets")
        #expect(Self.parse("Call the bank Friday", zone) == nil)
    }

    @Test("every weekend reads Saturday, Sunday")
    func weekendSummary() throws {
        let s = try #require(Self.parse("Trash every weekend", "America/New_York"))
        #expect(s.summary.hasSuffix("repeats every week on Saturday, Sunday"))
    }
}
