import Foundation

/// The signed JSON payload the Mac-side Claude Code bridge sends to the app.
public struct BridgeBatch: Codable, Equatable, Sendable {
    public static let maxItems = 200
    public static let maxTitle = 500
    public static let maxNotes = 5000

    public var v: Int
    public var batch: String
    public var issuedAt: TimeInterval
    public var label: String?
    public var items: [BridgeItem]

    public init(v: Int = 1, batch: String, issuedAt: TimeInterval, label: String?, items: [BridgeItem]) {
        self.v = v
        self.batch = batch
        self.issuedAt = issuedAt
        self.label = label
        self.items = items
    }

    /// Validates the whole batch (all-or-nothing) and converts it to store models. Times are read
    /// in `calendar`'s time zone (the phone's current one by default).
    public func models(calendar: Calendar = .current) throws -> BridgeImport {
        guard v == 1 else { throw BridgeError.unsupportedVersion(v) }
        guard BridgeIDs.isValid(batch) else { throw BridgeError.badBatchID(batch) }
        guard !items.isEmpty else { throw BridgeError.emptyBatch }
        guard items.count <= Self.maxItems else { throw BridgeError.tooManyItems(items.count) }
        let label = BridgeLabel.sanitize(self.label)
        var seen = Set<String>()
        var result = BridgeImport(events: [], reminders: [])
        for item in items {
            guard !item.id.isEmpty else { throw BridgeError.emptyID }
            guard BridgeIDs.isValid(item.id) else { throw BridgeError.badItemID(item.id) }
            guard seen.insert(item.id).inserted else { throw BridgeError.duplicateID(item.id) }
            try item.convert(label: label, calendar: calendar, into: &result)
        }
        return result
    }
}

public struct BridgeItem: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case reminder, event }
    public enum PriorityLevel: String, Codable, Sendable { case low, medium, high }

    public var id: String
    public var kind: Kind
    public var title: String
    public var notes: String?
    public var start: String
    public var end: String?
    public var location: String?
    public var url: String?
    public var recurrence: BridgeRecurrence?
    public var priority: PriorityLevel?

    public init(
        id: String, kind: Kind, title: String, notes: String? = nil, start: String, end: String? = nil,
        location: String? = nil, url: String? = nil, recurrence: BridgeRecurrence? = nil,
        priority: PriorityLevel? = nil
    ) {
        self.id = id; self.kind = kind; self.title = title; self.notes = notes; self.start = start
        self.end = end; self.location = location; self.url = url; self.recurrence = recurrence
        self.priority = priority
    }

    fileprivate func convert(label: String?, calendar: Calendar, into out: inout BridgeImport) throws {
        let trimmedTitle = title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !trimmedTitle.isEmpty else { throw BridgeError.emptyTitle(id: id) }
        guard title.count <= BridgeBatch.maxTitle else { throw BridgeError.titleTooLong(id: id) }
        if let notes, notes.count > BridgeBatch.maxNotes { throw BridgeError.notesTooLong(id: id) }
        if let url {
            guard let comps = URLComponents(string: url), let scheme = comps.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", let host = comps.host, !host.isEmpty
            else { throw BridgeError.badURL(id: id) }
        }

        let (startDate, startAllDay) = try BridgeDates.parse(start, field: "start", id: id, calendar: calendar)
        let rule = try recurrence.map { try $0.rule(id: id, start: startDate, calendar: calendar) }
        let finalNotes = BridgeLabel.appending(label, to: FormFields.trimmedOrNil(notes ?? "") == nil ? nil : notes)

        switch kind {
        case .reminder:
            out.reminders.append(Reminder(
                id: id, title: trimmedTitle, notes: finalNotes, dueDate: startDate,
                priority: priority.map(Self.icalPriority), recurrence: rule))
        case .event:
            var endDate: Date?
            if !startAllDay, let end {
                endDate = try BridgeDates.parseEnd(end, start: startDate, id: id, calendar: calendar)
                if let e = endDate, e <= startDate { endDate = nil }
            } else if let end {
                // Still validate the text, then drop it: an all-day event carries no end.
                _ = try BridgeDates.parseEnd(end, start: startDate, id: id, calendar: calendar)
            }
            out.events.append(Event(
                id: id, title: trimmedTitle, notes: finalNotes, start: startDate, end: endDate, isAllDay: startAllDay,
                location: location.flatMap(FormFields.trimmedOrNil), recurrence: rule, url: url))
        }
    }

    private static func icalPriority(_ level: PriorityLevel) -> Int {
        switch level {
        case .low: return ReminderPriority.low.icalValue!
        case .medium: return ReminderPriority.medium.icalValue!
        case .high: return ReminderPriority.high.icalValue!
        }
    }
}

public struct BridgeRecurrence: Codable, Equatable, Sendable {
    public var freq: RecurrenceRule.Frequency
    public var interval: Int?
    public var byDay: [String]?
    public var until: String?
    public var count: Int?

    public init(freq: RecurrenceRule.Frequency, interval: Int? = nil, byDay: [String]? = nil,
                until: String? = nil, count: Int? = nil) {
        self.freq = freq; self.interval = interval; self.byDay = byDay; self.until = until; self.count = count
    }

    fileprivate func rule(id: String, start: Date, calendar: Calendar) throws -> RecurrenceRule {
        if let interval, !(1...999).contains(interval) { throw BridgeError.badInterval(id: id) }
        if let count, !(1...1000).contains(count) { throw BridgeError.badCount(id: id) }
        let parsedDays: [Weekday]? = try byDay.map { names in
            try names.map { name in
                switch name.lowercased() {
                case "sun": return Weekday.sunday
                case "mon": return .monday
                case "tue": return .tuesday
                case "wed": return .wednesday
                case "thu": return .thursday
                case "fri": return .friday
                case "sat": return .saturday
                default: throw BridgeError.badWeekday(id: id, text: name)
                }
            }
        }
        var days: [Weekday]?
        if let parsedDays, !parsedDays.isEmpty {
            var seen = Set<Weekday>()
            days = parsedDays.filter { seen.insert($0).inserted }
        }
        var untilDate: Date?
        if let until {
            let (d, _) = try BridgeDates.parse(until, field: "until", id: id, calendar: calendar)
            let day = calendar.startOfDay(for: d)
            if day < calendar.startOfDay(for: start) { throw BridgeError.untilBeforeStart(id: id) }
            untilDate = day
        }
        return RecurrenceRule(frequency: freq, interval: interval ?? 1, byDay: days, count: count, until: untilDate)
    }
}

public struct BridgeImport: Equatable, Sendable {
    public var events: [Event]
    public var reminders: [Reminder]
    public init(events: [Event], reminders: [Reminder]) {
        self.events = events
        self.reminders = reminders
    }
}

/// Why a batch was rejected. `description` is the banner text shown to the user.
public enum BridgeError: Error, Equatable, CustomStringConvertible {
    case unsupportedVersion(Int)
    case emptyBatch
    case tooManyItems(Int)
    case emptyID
    case badItemID(String)
    case badBatchID(String)
    case duplicateID(String)
    case emptyTitle(id: String)
    case titleTooLong(id: String)
    case notesTooLong(id: String)
    case badDate(id: String, field: String, text: String)
    case nonexistentLocalTime(id: String, text: String)
    case untilBeforeStart(id: String)
    case badWeekday(id: String, text: String)
    case badInterval(id: String)
    case badCount(id: String)
    case badURL(id: String)
    case malformed
    case itemTooLarge(id: String)

    public var description: String {
        switch self {
        case .unsupportedVersion(let v): return "Claude batch rejected: unsupported version \(v)."
        case .emptyBatch: return "Claude batch rejected: it has no items."
        case .tooManyItems(let n): return "Claude batch rejected: \(n) items (the limit is \(BridgeBatch.maxItems))."
        case .emptyID: return "Claude batch rejected: an item has no id."
        case .badItemID(let id): return "Claude batch rejected: item id \"\(BridgeIDs.display(id))\" is not allowed (use 1-64 letters, digits, - or _)."
        case .badBatchID(let id): return "Claude batch rejected: batch id \"\(BridgeIDs.display(id))\" is not allowed (use 1-64 letters, digits, - or _)."
        case .duplicateID(let id): return "Claude batch rejected: item \"\(id)\" appears more than once."
        case .emptyTitle(let id): return "Claude batch rejected: item \"\(id)\" has no title."
        case .titleTooLong(let id): return "Claude batch rejected: item \"\(id)\" has a title over \(BridgeBatch.maxTitle) characters."
        case .notesTooLong(let id): return "Claude batch rejected: item \"\(id)\" has notes over \(BridgeBatch.maxNotes) characters."
        case .badDate(let id, let field, let text): return "Claude batch rejected: item \"\(id)\" has an invalid \(field) \"\(BridgeIDs.echo(text))\" (use yyyy-MM-dd or yyyy-MM-ddTHH:mm)."
        case .nonexistentLocalTime(let id, let text): return "Claude batch rejected: item \"\(id)\" time \(text) does not exist in this time zone (daylight saving gap)."
        case .untilBeforeStart(let id): return "Claude batch rejected: item \"\(id)\" repeats until a date before it starts."
        case .badWeekday(let id, let text): return "Claude batch rejected: item \"\(id)\" has an unknown weekday \"\(BridgeIDs.echo(text))\"."
        case .badInterval(let id): return "Claude batch rejected: item \"\(id)\" has a repeat interval below 1."
        case .badCount(let id): return "Claude batch rejected: item \"\(id)\" has a repeat count below 1."
        case .badURL(let id): return "Claude batch rejected: item \"\(id)\" has a link that is not http or https."
        case .malformed: return "Claude batch rejected: the link is damaged or unreadable."
        case .itemTooLarge(let id): return "Claude batch rejected: item \"\(id)\" is too large to send."
        }
    }
}

enum BridgeDates {
    /// Parses `yyyy-MM-dd` (all-day) or `yyyy-MM-ddTHH:mm`.
    static func parse(_ text: String, field: String, id: String, calendar: Calendar) throws -> (Date, Bool) {
        let bad = BridgeError.badDate(id: id, field: field, text: text)
        let parts = text.split(separator: "T", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 2, let datePart = parts.first else { throw bad }
        let d = datePart.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard d.count == 3, d[0].count == 4, d[1].count == 2, d[2].count == 2,
              let y = Int(d[0]), let mo = Int(d[1]), let day = Int(d[2]) else { throw bad }
        var comps = DateComponents(year: y, month: mo, day: day)
        var allDay = true
        if parts.count == 2 {
            let t = parts[1].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard t.count == 2, t[0].count == 2, t[1].count == 2,
                  let h = Int(t[0]), let mi = Int(t[1]), (0..<24).contains(h), (0..<60).contains(mi) else { throw bad }
            comps.hour = h
            comps.minute = mi
            allDay = false
        }
        // The y/m/d alone must be a real date (Feb 30 with a time is a bad date, not a DST gap).
        guard let dayOnly = calendar.date(from: DateComponents(year: y, month: mo, day: day)) else { throw bad }
        let dc = calendar.dateComponents([.year, .month, .day], from: dayOnly)
        guard dc.year == y, dc.month == mo, dc.day == day else { throw bad }
        guard var date = calendar.date(from: comps) else { throw bad }
        let unitSet: Set<Calendar.Component> = allDay ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute]
        func matches(_ d: Date) -> Bool {
            let got = calendar.dateComponents(unitSet, from: d)
            return got.year == y && got.month == mo && got.day == day && (allDay || (got.hour == comps.hour && got.minute == comps.minute))
        }
        if !matches(date) {
            // A date-only value that does not round-trip is not a real date (e.g. Feb 30).
            if allDay { throw bad }
            throw BridgeError.nonexistentLocalTime(id: id, text: text)
        }
        if !allDay {
            // DST overlap: the same wall time may occur twice; take the earlier instant.
            let earlier = date.addingTimeInterval(-3600)
            if matches(earlier) { date = earlier }
        }
        return (date, allDay)
    }

    /// An event end: a full date/time, or `HH:mm` on the start's day.
    static func parseEnd(_ text: String, start: Date, id: String, calendar: Calendar) throws -> Date {
        if text.count == 5, text.contains(":"), !text.contains("T") {
            let day = calendar.dateComponents([.year, .month, .day], from: start)
            let ymd = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
            return try parse("\(ymd)T\(text)", field: "end", id: id, calendar: calendar).0
        }
        return try parse(text, field: "end", id: id, calendar: calendar).0
    }
}

public enum BridgeLabel {
    static let maxLength = 32

    /// Lowercase `[a-z0-9-]`, one token, at most 32 characters; nil when nothing is left.
    public static func sanitize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var out = ""
        var pendingDash = false
        for scalar in raw.lowercased().unicodeScalars {
            let isAlnum = (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57)
            if isAlnum {
                if pendingDash && !out.isEmpty { out.append("-") }
                pendingDash = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        var cut = String(out.prefix(maxLength))
        while cut.hasSuffix("-") { cut.removeLast() }
        return cut.isEmpty ? nil : cut
    }

    /// `notes` with `%label` on its own last line, unless that exact token is already there.
    public static func appending(_ label: String?, to notes: String?) -> String? {
        guard let label else { return notes }
        let token = "%" + label
        guard let notes, !notes.isEmpty else { return token }
        let words = notes.split(whereSeparator: { $0.isWhitespace })
        if words.contains(where: { $0 == token }) { return notes }
        return notes + "\n" + token
    }
}


enum BridgeIDs {
    private static func allowed(_ u: Unicode.Scalar) -> Bool {
        (u.value >= 48 && u.value <= 57) || (u.value >= 65 && u.value <= 90)
            || (u.value >= 97 && u.value <= 122) || u == "-" || u == "_"
    }

    /// 1-64 characters of `[A-Za-z0-9_-]`; ids are written unescaped into `UID:` lines.
    static func isValid(_ id: String) -> Bool {
        let scalars = id.unicodeScalars
        return !scalars.isEmpty && scalars.count <= 64 && scalars.allSatisfy(allowed)
    }

    /// A banner-safe form: illegal characters shown as `?`, cut to 24 characters.
    /// Untrusted text echoed in a banner: at most 24 characters, control characters shown as "?".
    static func echo(_ text: String) -> String {
        String(text.prefix(24).map { ch in
            ch.unicodeScalars.contains { $0.properties.generalCategory == .control } ? Character("?") : ch
        })
    }

    static func display(_ id: String) -> String {
        String(String.UnicodeScalarView(id.unicodeScalars.prefix(24).map { allowed($0) ? $0 : "?" }))
    }
}
