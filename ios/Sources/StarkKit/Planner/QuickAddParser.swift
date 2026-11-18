import Foundation

/// What `QuickAddParser` found in a typed phrase. Nothing here is applied automatically; the Add
/// screen shows `summary` and applies the fields when the owner taps it.
///
/// `kind` uses `AppleItemRef.Kind` (event or reminder): the app's own `ItemKind` lives in the app
/// target, and the Kit cannot see it.
public struct QuickAddSuggestion: Equatable, Sendable {
    public var title: String
    /// Start of the day when `hasTime` is false, the exact start otherwise.
    public var start: Date?
    public var hasTime: Bool
    public var end: Date?
    public var recurrence: RecurrenceRule?
    /// `.reminder` for a leading "remind me to", "todo" or "task"; nil means the form keeps its kind.
    public var kind: AppleItemRef.Kind?
    public var summary: String

    public init(title: String, start: Date?, hasTime: Bool, end: Date?, recurrence: RecurrenceRule?,
                kind: AppleItemRef.Kind?, summary: String) {
        self.title = title
        self.start = start
        self.hasTime = hasTime
        self.end = end
        self.recurrence = recurrence
        self.kind = kind
        self.summary = summary
    }
}

/// The Add form's fields for a tapped suggestion. A nil field means "leave the form as it is".
public struct QuickAddFormValues: Equatable, Sendable {
    public var title: String
    public var kind: AppleItemRef.Kind?
    public var allDay: Bool?
    public var start: Date?
    /// Already offset for the Starts picker: its change handler adds (start - previous start) to
    /// the end, so this value makes the end land on the suggested one.
    public var endForPicker: Date?
    public var recurrence: RecurrenceRule?
}

extension QuickAddSuggestion {
    /// False while `title` is exactly what the last Apply produced: the cleaned title can still
    /// parse (a leftover "on friday"), and the row must not come back until the owner edits it.
    public static func shouldOffer(title: String, appliedTitle: String?) -> Bool {
        title != appliedTitle
    }

    /// `currentStart` is the Starts picker's value before the suggestion is applied.
    public func formValues(currentStart: Date) -> QuickAddFormValues {
        var values = QuickAddFormValues(title: title, kind: kind, recurrence: recurrence)
        if let start {
            values.start = start
            values.allDay = !hasTime
            let wanted = end ?? start.addingTimeInterval(EventSchedule.defaultDuration)
            values.endForPicker = EventSchedule.shiftedEnd(wanted, oldStart: start, newStart: currentStart)
        }
        return values
    }
}

/// Finds a date, time, repeat, duration and kind in a phrase like "Lunch with Sarah at 1pm
/// tomorrow". English only, on device, pure.
///
/// This does not use `NSDataDetector`: the detector reads the real clock and the system time zone
/// with no way to pass a reference date, so results could not be tested with a fixed `now` or
/// under another calendar. The rules here are small, anchored on whole words, and use the given
/// `calendar` for every day and clock calculation.
public enum QuickAddParser {
    private static let weekdayWord =
        "mon(?:day)?|tues?(?:day)?|wed(?:nesday)?|thu(?:rs?)?(?:day)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?"
    private static let fullWeekday = "sunday|monday|tuesday|wednesday|thursday|friday|saturday"
    private static let monthWord =
        "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    public static func parse(_ text: String, now: Date, calendar given: Calendar = .current) -> QuickAddSuggestion? {
        // All day and clock math runs on a Gregorian copy (same time zone and locale), so a phone
        // set to a Buddhist, Hebrew or Japanese calendar cannot shift a year or a month name.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = given.timeZone
        calendar.locale = given.locale
        var work = Work(text: text)
        var kind: AppleItemRef.Kind?
        var recurrence: RecurrenceRule?

        if work.remove(#"^\s*(?:(?:remind me|reminder)\s+to\s+|(?:todo|to-do|task)\s*:\s*)"#) != nil {
            kind = .reminder
        }
        recurrence = parseRecurrence(&work)

        let today = calendar.startOfDay(for: now)
        var start: Date?
        var hasTime = false

        let relative = work.remove(#"\bin\s+(\d{1,3})\s+(hours?|hrs?|minutes?|mins?)\b"#) { m -> Date? in
            let n = Int(m[1])!
            let minutes = m[2].lowercased().hasPrefix("h") ? n * 60 : n
            return calendar.date(byAdding: .minute, value: minutes, to: now)
        }

        let snapshot = work.text
        var endClock: (hour: Int, minute: Int)?
        var clock: (hour: Int, minute: Int)?
        let rejectionsAtStart = work.rejections
        if let range = parseRange(&work) {
            clock = range.start
            endClock = range.end
        }
        // A refused range ("6pm-5pm") is not a date-looking token.
        work.rejections = rejectionsAtStart
        if clock == nil { clock = parseTime(&work) }
        let rejectionsBefore = work.rejections
        let day = parseDay(&work, today: today, calendar: calendar)
        if day == nil && work.rejections > rejectionsBefore {
            // A date-looking token was refused ("1/2 gallon"): do not let a time pick the day.
            work.text = snapshot
            clock = nil
            endClock = nil
        }
        if recurrence == nil { recurrence = parseTrailingRepeat(&work) }

        if let day {
            if let clock {
                start = at(day, clock, calendar)
                hasTime = true
            } else {
                start = day
            }
        } else if let clock {
            hasTime = true
            // No day given: the next time this clock reading occurs (for a weekly rule, on one
            // of its days).
            start = nextOccurrence(of: clock, days: recurrence?.byDay, now: now, today: today, calendar: calendar)
        } else if let relative {
            start = QuarterHour.nextAfter(relative, calendar: calendar)
            hasTime = true
        } else if let days = recurrence?.byDay {
            // "Trash every tuesday": the start is an occurrence, so begin on the next matching day.
            start = nextOccurrence(of: nil, days: days, now: now, today: today, calendar: calendar)
        }

        var end: Date?
        var rangeEnd: Date?
        if hasTime, let start {
            // A duration phrase is always consumed; an explicit range wins over it.
            if let m = work.remove(#"\bfor\s+(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m)\b"#) {
                let value = Double(m[1])!
                let seconds = m[2].lowercased().hasPrefix("h") ? value * 3600 : value * 60
                end = start.addingTimeInterval(seconds)
            }
            if let endClock {
                end = at(calendar.startOfDay(for: start), endClock, calendar)
                rangeEnd = end
            }
        }

        let title = work.cleanedTitle
        guard !title.isEmpty, start != nil || recurrence != nil || kind != nil else { return nil }

        return QuickAddSuggestion(
            title: title, start: start, hasTime: hasTime, end: end, recurrence: recurrence, kind: kind,
            summary: summary(start: start, hasTime: hasTime, rangeEnd: rangeEnd, recurrence: recurrence, kind: kind,
                             now: now, calendar: calendar))
    }

    /// The first day on or after today (with a clock time: strictly after `now`) on one of `days`.
    private static func nextOccurrence(of clock: (hour: Int, minute: Int)?, days: [Weekday]?, now: Date,
                                       today: Date, calendar: Calendar) -> Date? {
        let allowed = days.map { Set($0) }
        for offset in 0..<8 {
            guard let d = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if let allowed, !allowed.contains(weekday(of: d, calendar)) { continue }
            guard let clock else { return d }
            let candidate = at(d, clock, calendar)
            if candidate > now { return candidate }
        }
        return nil
    }

    // MARK: - Repeat

    private static func parseRecurrence(_ work: inout Work) -> RecurrenceRule? {
        let list = "(?:\(weekdayWord))"
        if let m = work.remove(#"\bevery\s+(weekday|weekend)s?\b"#) {
            let days: [Weekday] = m[1].lowercased() == "weekday"
                ? [.monday, .tuesday, .wednesday, .thursday, .friday] : [.saturday, .sunday]
            return RecurrenceRule(frequency: .weekly, byDay: days)
        }
        if let m = work.remove(#"\bevery\s+(\#(list)(?:\s*(?:,|and|&)\s*\#(list))*)\b"#) {
            var days: [Weekday] = []
            for word in m[1].lowercased().split(whereSeparator: { !$0.isLetter }) where word != "and" {
                if let d = weekdayFromPrefix(String(word)), !days.contains(d) { days.append(d) }
            }
            return RecurrenceRule(frequency: .weekly, byDay: days)
        }
        if let m = work.remove(#"\bevery\s+(\d{1,3})\s+(day|week|month|year)s?\b"#) {
            let n = max(1, Int(m[1])!)
            return RecurrenceRule(frequency: frequency(m[2]), interval: n)
        }
        if let m = work.remove(#"\bevery\s+(day|week|month|year)\b"#) {
            return RecurrenceRule(frequency: frequency(m[1]))
        }
        return nil
    }

    /// "daily", "weekly", "monthly", "yearly", "annually" count only as the last word ("Vitamins
    /// daily"), so "Weekly report" stays a title.
    private static func parseTrailingRepeat(_ work: inout Work) -> RecurrenceRule? {
        work.remove(#"\b(daily|weekly|monthly|yearly|annually)\W*$"#).map { RecurrenceRule(frequency: frequency($0[1])) }
    }

    private static func frequency(_ word: String) -> RecurrenceRule.Frequency {
        switch word.lowercased().prefix(1) {
        case "d": return .daily
        case "w": return .weekly
        case "m": return .monthly
        default: return .yearly // "year", "yearly", "annually"
        }
    }

    private static func weekdayFromPrefix(_ word: String) -> Weekday? {
        let names: [(String, Weekday)] = [("sun", .sunday), ("mon", .monday), ("tue", .tuesday), ("wed", .wednesday),
                                          ("thu", .thursday), ("fri", .friday), ("sat", .saturday)]
        return names.first { word.hasPrefix($0.0) }?.1
    }

    // MARK: - Time

    /// "1-2pm", "1pm-2pm", "1 to 2pm", "from 1pm to 2pm", "13:00-14:30", "9am until 10:30am".
    /// It needs a clock cue (am/pm, or h:mm on both sides with "at"/"from"/"@" or two-digit
    /// hours), so "Call 3-4" and "Chapter 3-4" stay text. A missing meridiem takes the other
    /// side's, and the reading must end after it starts; otherwise the text is left alone.
    private struct ClockRange {
        var start: (hour: Int, minute: Int)
        var end: (hour: Int, minute: Int)
    }

    private static func parseRange(_ work: inout Work) -> ClockRange? {
        let t = #"(\d{1,2})(?::([0-5]\d))?\s*(am|pm|a\.m\.|p\.m\.)?"#
        let sep = #"\s*(?:-|\x{2013}|\x{2014}|\bto\b|\buntil\b|\btill\b)\s*"#
        let pattern = #"(?<![\d:/.])(?:\b(at|from)\s+|(@)\s*)?"# + t + sep + t + #"(?![\d:a-z])"#
        return work.remove(pattern) { m -> ClockRange? in
            let lead = !(m[1] + m[2]).isEmpty
            let (h1, m1, a1) = (Int(m[3])!, Int(m[4]), m[5].lowercased())
            let (h2, m2, a2) = (Int(m[6])!, Int(m[7]), m[8].lowercased())
            if a1.isEmpty && a2.isEmpty {
                // 24 hour reading: colons on both sides, a lead word or two-digit hours.
                guard let m1, let m2, lead || (m[3].count == 2 && m[6].count == 2), h1 < 24, h2 < 24 else { return nil }
                let s = h1 * 60 + m1, e = h2 * 60 + m2
                return s < e ? ClockRange(start: (h1, m1), end: (h2, m2)) : nil
            }
            func minutes(_ hour: Int, _ minute: Int?, pm: Bool) -> Int? {
                guard (1...12).contains(hour) else { return nil }
                return (hour % 12 + (pm ? 12 : 0)) * 60 + (minute ?? 0)
            }
            let startFixed: Bool? = a1.isEmpty ? nil : a1.hasPrefix("p")
            let endFixed: Bool? = a2.isEmpty ? nil : a2.hasPrefix("p")
            let startOptions = startFixed.map { [$0] } ?? [endFixed!, !endFixed!]
            let endOptions = endFixed.map { [$0] } ?? [startFixed!, !startFixed!]
            for sp in startOptions {
                for ep in endOptions {
                    guard let s = minutes(h1, m1, pm: sp), let e = minutes(h2, m2, pm: ep), s < e else { continue }
                    return ClockRange(start: (s / 60, s % 60), end: (e / 60, e % 60))
                }
            }
            return nil
        }
    }

    private static func parseTime(_ work: inout Work) -> (hour: Int, minute: Int)? {
        let lead = #"(?:\bat\s+|@\s*)"#
        let ampm = work.remove(lead + #"?\b(\d{1,2})(?::([0-5]\d))?\s*(am|pm|a\.m\.|p\.m\.)(?![a-z])"#) { m -> (hour: Int, minute: Int)? in
            guard let h = Int(m[1]), (1...12).contains(h) else { return nil }
            return (h % 12 + (m[3].lowercased().hasPrefix("p") ? 12 : 0), Int(m[2]) ?? 0)
        }
        if let ampm { return ampm }
        // A bare h:mm ("John 3:16") is only a time after "at" or "@".
        if let m = work.remove(lead + #"(?<![\d:])([01]?\d|2[0-3]):([0-5]\d)(?![\d:])"#) {
            return (Int(m[1])!, Int(m[2])!)
        }
        if let m = work.remove(#"(?:\bat\s+|@\s*)\b(noon|midnight)\b"#) {
            return (m[1].lowercased() == "noon" ? 12 : 0, 0)
        }
        return nil
    }

    // MARK: - Day

    private static func parseDay(_ work: inout Work, today: Date, calendar: Calendar) -> Date? {
        let lead = #"(?:\b(?:on|by|from|at)\s+)?"#
        let monthLead = #"(?:\b(?:on|by|from|at|in)\s+)?"#
        /// The lone word "may" is only May after on/by/in or when written with a capital M.
        func mayOK(_ whole: String, _ word: String) -> Bool {
            guard word.lowercased() == "may" else { return true }
            if word.first?.isUppercase == true { return true }
            let w = whole.lowercased()
            return w.hasPrefix("on ") || w.hasPrefix("by ") || w.hasPrefix("in ")
        }
        func plus(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: days, to: today) }

        if let m = work.remove(lead + #"\b((?:tomorrow|tmrw)|(?<=\S\s)(?:today|tonight))\b(?![\'\x{2019}])"#) {
            return plus(["tomorrow", "tmrw"].contains(m[1].lowercased()) ? 1 : 0)
        }
        if let m = work.remove(#"\bin\s+(\d{1,3})\s+(days?|weeks?|months?)\b"#) {
            let n = Int(m[1])!
            switch m[2].lowercased().prefix(1) {
            case "d": return plus(n)
            case "w": return plus(n * 7)
            default: return calendar.date(byAdding: .month, value: n, to: today)
            }
        }
        if let m = work.remove(#"\bnext\s+(week|month)\b"#) {
            return m[1].lowercased() == "week" ? plus(7) : calendar.date(byAdding: .month, value: 1, to: today)
        }
        if let m = work.remove(#"\b(?:(?:on|by|before)\s+(this\s+|next\s+)?|(this\s+|next\s+))(\#(fullWeekday))\b"#) {
            let target = weekdayFromPrefix(m[3].lowercased())!.rawValue + 1
            let current = calendar.component(.weekday, from: today)
            let modifier = (m[1] + m[2]).trimmingCharacters(in: .whitespaces).lowercased()
            if modifier == "this" { return plus((target - current + 7) % 7) }
            // The coming one, strictly after today (1...7 days).
            let coming = (target - current + 6) % 7 + 1
            guard modifier == "next" else { return plus(coming) }
            // "next friday" skips a Friday that is still in this (Monday to Sunday) week.
            let mondayIndex = (current + 5) % 7
            return plus(mondayIndex + coming <= 6 ? coming + 7 : coming)
        }
        let a = work.remove(monthLead + #"\b(\#(monthWord))\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?!\s*(?::|am\b|pm\b))(?:,?\s+(\d{4})\b)?"#) { m -> Date? in
            guard mayOK(m[0], m[1]) else { return nil }
            let month = monthNames.firstIndex { m[1].lowercased().hasPrefix($0) }! + 1
            return resolve(month: month, day: Int(m[2])!, year: Int(m[3]), today: today, calendar: calendar)
        }
        if let a { return a }
        let b = work.remove(monthLead + #"\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(\#(monthWord))\b(?:,?\s+(\d{4})\b)?"#) { m -> Date? in
            guard mayOK(m[0], m[2]) else { return nil }
            let month = monthNames.firstIndex { m[2].lowercased().hasPrefix($0) }! + 1
            return resolve(month: month, day: Int(m[1])!, year: Int(m[3]), today: today, calendar: calendar)
        }
        if let b { return b }
        // A bare m/d is also a fraction ("1/2 gallon"): it needs a year or on/by/due/before/until.
        return work.remove(#"(?:\b(on|by|due|before|until)\s+)?(?<![\d/])(\d{1,2})/(\d{1,2})(?:/(\d{2}|\d{4}))?(?![\d/])"#) { m -> Date? in
            var year = Int(m[4])
            if year == nil && m[1].isEmpty { return nil }
            if let y = year, y < 100 { year = 2000 + y }
            return resolve(month: Int(m[2])!, day: Int(m[3])!, year: year, today: today, calendar: calendar)
        }
    }

    private static func resolve(month: Int, day: Int, year: Int?, today: Date, calendar: Calendar) -> Date? {
        func make(_ y: Int) -> Date? {
            guard let d = calendar.date(from: DateComponents(year: y, month: month, day: day)),
                  calendar.component(.month, from: d) == month, calendar.component(.day, from: d) == day
            else { return nil }
            return d
        }
        if let year { return make(year) }
        let thisYear = calendar.component(.year, from: today)
        if let d = make(thisYear), d >= today { return d }
        return make(thisYear + 1)
    }

    private static func at(_ day: Date, _ clock: (hour: Int, minute: Int), _ calendar: Calendar) -> Date {
        calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day) ?? day
    }

    private static func weekday(of date: Date, _ calendar: Calendar) -> Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: date) - 1) ?? .sunday
    }

    // MARK: - Summary

    private static func summary(start: Date?, hasTime: Bool, rangeEnd: Date?, recurrence: RecurrenceRule?,
                                kind: AppleItemRef.Kind?, now: Date, calendar: Calendar) -> String {
        var parts: [String] = []
        if kind == .reminder { parts.append("Reminder") }
        if let start {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)
            var label: String
            if calendar.isDate(start, inSameDayAs: now) {
                label = "Today"
            } else if let tomorrow, calendar.isDate(start, inSameDayAs: tomorrow) {
                label = "Tomorrow"
            } else {
                let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: now)
                label = format(start, sameYear ? "EEE, MMM d" : "EEE, MMM d, yyyy", calendar)
            }
            if hasTime {
                // The pattern follows the locale's 12 or 24 hour setting ("h:mm a" or "HH:mm").
                let pattern = DateFormatter.dateFormat(fromTemplate: "jm", options: 0,
                                                       locale: calendar.locale ?? .current) ?? "h:mm a"
                if let rangeEnd {
                    label += ", " + format(start, pattern, calendar) + " to " + format(rangeEnd, pattern, calendar)
                } else {
                    label += " at " + format(start, pattern, calendar)
                }
            }
            parts.append(label)
        }
        if let recurrence {
            let s = recurrence.summary
            parts.append("repeats " + s.prefix(1).lowercased() + s.dropFirst())
        }
        guard let first = parts.first else { return "" }
        parts[0] = first.prefix(1).uppercased() + first.dropFirst()
        return parts.joined(separator: ", ")
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = pattern
        // Newer ICU puts a narrow no-break space before AM/PM; a plain space reads the same.
        return f.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ")
    }

    // MARK: - Text editing

    /// The phrase being consumed. `remove` deletes the first case-insensitive match and returns
    /// its capture groups (index 0 is the whole match, a missing group is "").
    private struct Work {
        var text: String
        /// How many regex matches `transform` refused (a date-looking token that is not a date).
        var rejections = 0

        mutating func remove(_ pattern: String) -> [String]? {
            remove(pattern) { $0 }
        }

        /// Consumes the first match for which `transform` returns a value; a match it rejects
        /// ("13pm", "Feb 30") stays in the text.
        mutating func remove<T>(_ pattern: String, _ transform: ([String]) -> T?) -> T? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                var groups: [String] = []
                for i in 0..<m.numberOfRanges {
                    let r = m.range(at: i)
                    groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
                }
                if let value = transform(groups) {
                    text = ns.replacingCharacters(in: m.range, with: " ")
                    return value
                }
                rejections += 1
            }
            return nil
        }

        var cleanedTitle: String {
            let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
        }
    }
}
