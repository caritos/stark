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

    /// Nil for empty or whitespace-only dictation. Text the parser does not understand becomes a
    /// reminder with no date. A suggestion with a start is an event unless the phrase said
    /// "remind me to"/"todo"/"task"; a repeat with no date becomes a date-only reminder from today
    /// (a repeating reminder needs a due date).
    public static func make(dictation: String, now: Date, calendar: Calendar = .current) -> WatchAddDraft? {
        let text = dictation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let suggestion = QuickAddParser.parse(text, now: now, calendar: calendar) else {
            return WatchAddDraft(kind: .reminder, title: text, start: nil, end: nil, isAllDay: false,
                                 recurrence: nil, summary: "Reminder, no date")
        }
        let values = suggestion.formValues(currentStart: suggestion.start ?? now)
        let isEvent = suggestion.start != nil && suggestion.kind != .reminder
        if isEvent {
            return WatchAddDraft(kind: .event, title: suggestion.title, start: suggestion.start,
                                 end: suggestion.end ?? suggestion.start?.addingTimeInterval(EventSchedule.defaultDuration),
                                 isAllDay: values.allDay ?? false, recurrence: suggestion.recurrence,
                                 summary: suggestion.summary)
        }
        var start = suggestion.start
        var hasTime = suggestion.hasTime
        if start == nil, suggestion.recurrence != nil {
            start = calendar.startOfDay(for: now)
            hasTime = false
        }
        return WatchAddDraft(kind: .reminder, title: suggestion.title, start: start, end: nil,
                             isAllDay: start != nil && !hasTime, recurrence: suggestion.recurrence,
                             summary: suggestion.summary)
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
