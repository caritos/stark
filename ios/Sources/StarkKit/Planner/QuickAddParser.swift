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

    public static func parse(_ text: String, now: Date, calendar: Calendar = .current) -> QuickAddSuggestion? {
        var work = Work(text: text)
        var kind: AppleItemRef.Kind?
        var recurrence: RecurrenceRule?

        if work.remove(#"^\s*(?:remind me to|remind me|reminder|todo|to-do|task)\b[:,]?\s+"#) != nil {
            kind = .reminder
        }
        recurrence = parseRecurrence(&work)

        let today = calendar.startOfDay(for: now)
        var start: Date?
        var hasTime = false
        var day: Date?
        var clock: (hour: Int, minute: Int)?

        if let m = work.remove(#"\bin\s+(\d{1,3})\s+(hours?|hrs?|minutes?|mins?)\b"#) {
            let n = Int(m[1])!
            let minutes = m[2].lowercased().hasPrefix("h") ? n * 60 : n
            start = calendar.date(byAdding: .minute, value: minutes, to: now)
            hasTime = true
        } else {
            clock = parseTime(&work)
            day = parseDay(&work, today: today, calendar: calendar)
        }

        if start == nil {
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
                let allowed = recurrence?.byDay.map { Set($0) }
                for offset in 0..<8 {
                    guard let d = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                    let candidate = at(d, clock, calendar)
                    if let allowed, !allowed.contains(weekday(of: d, calendar)) { continue }
                    if candidate > now { start = candidate; break }
                }
            }
        }

        var end: Date?
        if hasTime, let start,
           let m = work.remove(#"\bfor\s+(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m)\b"#) {
            let value = Double(m[1])!
            let seconds = m[2].lowercased().hasPrefix("h") ? value * 3600 : value * 60
            end = start.addingTimeInterval(seconds)
        }

        let title = work.cleanedTitle
        guard !title.isEmpty, start != nil || recurrence != nil || kind != nil else { return nil }

        return QuickAddSuggestion(
            title: title, start: start, hasTime: hasTime, end: end, recurrence: recurrence, kind: kind,
            summary: summary(start: start, hasTime: hasTime, recurrence: recurrence, kind: kind,
                             now: now, calendar: calendar))
    }

    // MARK: - Repeat

    private static func parseRecurrence(_ work: inout Work) -> RecurrenceRule? {
        let list = "(?:\(weekdayWord))"
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
        if let m = work.remove(#"\b(daily|weekly|monthly|yearly|annually)\b"#) {
            return RecurrenceRule(frequency: frequency(m[1]))
        }
        return nil
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

    private static func parseTime(_ work: inout Work) -> (hour: Int, minute: Int)? {
        let lead = #"(?:\b(?:at|@)\s+)?"#
        if let m = work.remove(lead + #"\b(\d{1,2})(?::([0-5]\d))?\s*(am|pm|a\.m\.|p\.m\.)(?![a-z])"#) {
            let h = Int(m[1])!
            if (1...12).contains(h) {
                let pm = m[3].lowercased().hasPrefix("p")
                return (h % 12 + (pm ? 12 : 0), Int(m[2]) ?? 0)
            }
        }
        if let m = work.remove(lead + #"(?<![\d:])([01]?\d|2[0-3]):([0-5]\d)(?![\d:])"#) {
            return (Int(m[1])!, Int(m[2])!)
        }
        if let m = work.remove(lead + #"\b(noon|midnight)\b"#) {
            return (m[1].lowercased() == "noon" ? 12 : 0, 0)
        }
        return nil
    }

    // MARK: - Day

    private static func parseDay(_ work: inout Work, today: Date, calendar: Calendar) -> Date? {
        let lead = #"(?:\b(?:on|by|from|at)\s+)?"#
        func plus(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: days, to: today) }

        if let m = work.remove(lead + #"\b(today|tonight|tomorrow|tmrw)\b"#) {
            return plus(m[1].lowercased().hasPrefix("tom") || m[1].lowercased() == "tmrw" ? 1 : 0)
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
        if let m = work.remove(lead + #"\b(?:(?:next|this)\s+)?(\#(fullWeekday))\b"#) {
            let target = weekdayFromPrefix(m[1].lowercased())!.rawValue + 1
            let current = calendar.component(.weekday, from: today)
            var delta = (target - current + 7) % 7
            if delta == 0 { delta = 7 }
            return plus(delta)
        }
        if let m = work.remove(lead + #"\b(\#(monthWord))\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?!\s*(?::|am\b|pm\b))(?:,?\s+(\d{4})\b)?"#) {
            let month = monthNames.firstIndex { m[1].lowercased().hasPrefix($0) }! + 1
            return resolve(month: month, day: Int(m[2])!, year: Int(m[3]), today: today, calendar: calendar)
        }
        if let m = work.remove(lead + #"\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(\#(monthWord))\b(?:,?\s+(\d{4})\b)?"#) {
            let month = monthNames.firstIndex { m[2].lowercased().hasPrefix($0) }! + 1
            return resolve(month: month, day: Int(m[1])!, year: Int(m[3]), today: today, calendar: calendar)
        }
        if let m = work.remove(lead + #"(?<![\d/])(\d{1,2})/(\d{1,2})(?:/(\d{2}|\d{4}))?(?![\d/])"#) {
            var year = Int(m[3])
            if let y = year, y < 100 { year = 2000 + y }
            return resolve(month: Int(m[1])!, day: Int(m[2])!, year: year, today: today, calendar: calendar)
        }
        return nil
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

    private static func summary(start: Date?, hasTime: Bool, recurrence: RecurrenceRule?,
                                kind: AppleItemRef.Kind?, now: Date, calendar: Calendar) -> String {
        var parts: [String] = []
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
            if hasTime { label += " at " + format(start, "h:mm a", calendar) }
            parts.append(label)
        }
        if let recurrence {
            let s = recurrence.summary
            parts.append("repeats " + s.prefix(1).lowercased() + s.dropFirst())
        }
        if parts.isEmpty { return kind == .reminder ? "Reminder" : "" }
        let joined = parts.joined(separator: ", ")
        return start == nil ? joined.prefix(1).uppercased() + joined.dropFirst() : joined
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = pattern
        return f.string(from: date)
    }

    // MARK: - Text editing

    /// The phrase being consumed. `remove` deletes the first case-insensitive match and returns
    /// its capture groups (index 0 is the whole match, a missing group is "").
    private struct Work {
        var text: String

        mutating func remove(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            let ns = text as NSString
            guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            text = ns.replacingCharacters(in: m.range, with: " ")
            return groups
        }

        var cleanedTitle: String {
            let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
        }
    }
}
