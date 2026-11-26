import Foundation

/// A dictated phrase turned into something the owner confirms on the watch. `Codable` because a
/// later task sends it to the iPhone, which does the real write (EventKit writes are unavailable
/// on watchOS).
public struct WatchAddDraft: Equatable, Codable, Sendable {
    /// `.event` or `.reminder`.
    public var kind: AppleItemRef.Kind
    public var title: String
    public var start: Date?
    public var end: Date?
    public var isAllDay: Bool
    public var recurrence: RecurrenceRule?
    /// One line for the confirm screen.
    public var summary: String

    public init(kind: AppleItemRef.Kind, title: String, start: Date?, end: Date?, isAllDay: Bool,
                recurrence: RecurrenceRule?, summary: String) {
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.summary = summary
    }

    /// Nil for empty or whitespace-only dictation. Everything is a reminder unless the phrase says
    /// "event" or "appointment" ("remind me to"/"todo"/"task" still wins); owner call 2026-11-26.
    /// With no date, including text the parser does not understand, it is date-only, today, so it
    /// shows in Up Next.
    public static func make(dictation: String, now: Date, calendar: Calendar = .current) -> WatchAddDraft? {
        let text = dictation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let prefixed = matches(text, #"^(?:(?:remind me|reminder)\s+to\s+|(?:todo|to-do|task)\s*:)"#)
        let isEvent = !prefixed && matches(text, #"\b(?:event|appointment)\b"#)

        // A reminder is parsed as one even without the words, so a closing "Friday" is read and no
        // end time is made. A leading "event" is only the marker, not part of the title.
        var phrase = prefixed ? text : "remind me to " + text
        if isEvent {
            let stripped = text.replacingOccurrences(of: #"^(?:new\s+)?event\b[\s:,]*"#, with: "",
                                                     options: [.regularExpression, .caseInsensitive])
            phrase = stripped.isEmpty ? text : stripped
        }
        let suggestion = QuickAddParser.parse(phrase, now: now, calendar: calendar)

        let title = suggestion?.title ?? (isEvent ? phrase : text)
        let start = suggestion?.start ?? calendar.startOfDay(for: now)
        let hasTime = suggestion?.start != nil && suggestion?.hasTime == true
        let recurrence = suggestion?.recurrence
        var summary = suggestion?.summary ?? ""
        if suggestion?.start == nil && recurrence == nil { summary = isEvent ? "Today" : "Reminder, Today" }
        let end = isEvent && hasTime
            ? suggestion?.end ?? start.addingTimeInterval(EventSchedule.defaultDuration) : nil
        return WatchAddDraft(kind: isEvent ? .event : .reminder, title: title, start: start, end: end,
                             isAllDay: !hasTime, recurrence: recurrence, summary: summary)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    public func newEvent() -> NewEvent? {
        guard kind == .event, let start else { return nil }
        return NewEvent(title: title, start: start, end: end, isAllDay: isAllDay, recurrence: recurrence)
    }

    public func newReminder() -> NewReminder? {
        guard kind == .reminder else { return nil }
        return NewReminder(title: title, due: start, dueHasTime: start != nil && !isAllDay, recurrence: recurrence)
    }
}
