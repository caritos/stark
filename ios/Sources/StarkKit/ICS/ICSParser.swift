import Foundation

public struct ICSParseResult {
    public let events: [Event]
    public let reminders: [Reminder]
    public let warnings: [String]

    public init(events: [Event], reminders: [Reminder], warnings: [String]) {
        self.events = events
        self.reminders = reminders
        self.warnings = warnings
    }
}

public enum ICSParser {
    public static func parse(_ content: String) -> ICSParseResult {
        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }

        var events: [Event] = []
        var reminders: [Reminder] = []
        var warnings: [String] = []
        var currentBlock: [String]?
        var currentKind: String?

        for line in lines {
            if line == "BEGIN:VEVENT" || line == "BEGIN:VTODO" {
                currentBlock = []
                currentKind = line == "BEGIN:VEVENT" ? "VEVENT" : "VTODO"
                continue
            }
            if line == "END:VEVENT" || line == "END:VTODO" {
                defer { currentBlock = nil; currentKind = nil }
                guard let block = currentBlock, let kind = currentKind else { continue }
                if kind == "VEVENT" {
                    if let event = parseEvent(block) {
                        events.append(event)
                    } else {
                        warnings.append("skipped malformed VEVENT block: missing UID/SUMMARY/DTSTART")
                    }
                } else {
                    if let reminder = parseReminder(block) {
                        reminders.append(reminder)
                    } else {
                        warnings.append("skipped malformed VTODO block: missing UID/SUMMARY")
                    }
                }
                continue
            }
            currentBlock?.append(line)
        }

        return ICSParseResult(events: events, reminders: reminders, warnings: warnings)
    }

    private static func properties(_ block: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for line in block {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].split(separator: ";").first.map(String.init) ?? ""
            result[key] = String(line[line.index(after: colon)...])
        }
        return result
    }

    private static func exceptionDates(_ block: [String]) -> [Date] {
        block.filter { $0.hasPrefix("EXDATE") }.compactMap { line -> Date? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return ICSDateFormat.parse(String(line[line.index(after: colon)...]))?.date
        }
    }

    /// `X-STARK-ATTENDED` / `X-STARK-SKIPPED` lines in file order, so parse -> serialize is
    /// byte-stable. Unparseable dates and unknown `X-STARK-*` names are ignored.
    private static func outcomes(_ block: [String]) -> [EventOutcomeRecord] {
        block.compactMap { line -> EventOutcomeRecord? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[line.startIndex..<colon].split(separator: ";").first.map(String.init) ?? ""
            let outcome: EventOutcome
            switch name {
            case "X-STARK-ATTENDED": outcome = .attended
            case "X-STARK-SKIPPED": outcome = .skipped
            default: return nil
            }
            guard let date = ICSDateFormat.parse(String(line[line.index(after: colon)...]))?.date else { return nil }
            return EventOutcomeRecord(date: date, outcome: outcome)
        }
    }

    private static func parseEvent(_ block: [String]) -> Event? {
        let props = properties(block)
        guard let id = props["UID"], let title = props["SUMMARY"],
              let dtstartRaw = props["DTSTART"],
              let (start, allDay) = ICSDateFormat.parse(dtstartRaw) else { return nil }

        return Event(
            id: id,
            title: unescape(title),
            notes: props["DESCRIPTION"].map(unescape),
            start: start,
            end: props["DTEND"].flatMap { ICSDateFormat.parse($0)?.date },
            isAllDay: allDay,
            location: props["LOCATION"].map(unescape),
            recurrence: props["RRULE"].flatMap(RRuleCodec.decode),
            exceptionDates: exceptionDates(block),
            outcomes: outcomes(block),
            url: props["URL"]
        )
    }

    private static func parseReminder(_ block: [String]) -> Reminder? {
        let props = properties(block)
        guard let id = props["UID"], let title = props["SUMMARY"] else { return nil }

        return Reminder(
            id: id,
            title: unescape(title),
            notes: props["DESCRIPTION"].map(unescape),
            dueDate: props["DUE"].flatMap { ICSDateFormat.parse($0)?.date },
            isCompleted: props["STATUS"] == "COMPLETED",
            completedDate: props["COMPLETED"].flatMap { ICSDateFormat.parse($0)?.date },
            priority: props["PRIORITY"].flatMap(Int.init),
            recurrence: props["RRULE"].flatMap(RRuleCodec.decode),
            exceptionDates: exceptionDates(block)
        )
    }

    /// Single left-to-right pass, not sequential `replacingOccurrences` calls. Sequential
    /// replacement (old approach: `\n` → newline, then `\;` → `;`, then `\,` → `,`, then
    /// `\\` → `\`, in that order) misparses an escaped literal backslash immediately
    /// followed by the letter "n" (i.e. `\\n` in the ICS text, meaning "a backslash, then
    /// n") — the `\n` → newline rule fires on the second and third characters of that
    /// three-character sequence before the `\\` → `\` rule ever gets a chance to consume
    /// the first two, producing a spurious newline instead of `\` + `n`. Scanning
    /// character-by-character and deciding the escape from the single character following
    /// each backslash avoids the ambiguity entirely.
    private static func unescape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var iterator = text.makeIterator()
        while let char = iterator.next() {
            guard char == "\\" else {
                result.append(char)
                continue
            }
            guard let next = iterator.next() else {
                result.append(char)
                break
            }
            switch next {
            case "n": result.append("\n")
            case ";": result.append(";")
            case ",": result.append(",")
            case "\\": result.append("\\")
            default:
                result.append(char)
                result.append(next)
            }
        }
        return result
    }
}
