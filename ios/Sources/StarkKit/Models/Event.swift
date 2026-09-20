import Foundation

/// What the user did about one occurrence of an event.
public enum EventOutcome: String, Equatable, Codable, Sendable {
    case attended
    case skipped
}

/// One recorded outcome. `date` is the occurrence's start; records are matched to occurrences by
/// calendar day (like `exceptionDates`), so a later change of time-of-day keeps the mark.
public struct EventOutcomeRecord: Equatable, Codable, Sendable {
    public var date: Date
    public var outcome: EventOutcome

    public init(date: Date, outcome: EventOutcome) {
        self.date = date
        self.outcome = outcome
    }
}

public struct Event: Equatable, Codable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var notes: String?
    public var start: Date
    public var end: Date?
    public var isAllDay: Bool
    public var location: String?
    public var recurrence: RecurrenceRule?
    public var exceptionDates: [Date]
    public var outcomes: [EventOutcomeRecord]

    public init(
        id: String = UUID().uuidString,
        title: String,
        notes: String? = nil,
        start: Date,
        end: Date? = nil,
        isAllDay: Bool = false,
        location: String? = nil,
        recurrence: RecurrenceRule? = nil,
        exceptionDates: [Date] = [],
        outcomes: [EventOutcomeRecord] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.recurrence = recurrence
        self.exceptionDates = exceptionDates
        self.outcomes = outcomes
    }

    /// A copy starting at `newStart`, with `end` (if any) shifted by the same delta so the
    /// event's duration is preserved. Every other field is left untouched.
    public func settingStart(_ newStart: Date) -> Event {
        var copy = self
        copy.start = newStart
        if let end {
            copy.end = end.addingTimeInterval(newStart.timeIntervalSince(start))
        }
        return copy
    }

    /// A copy moved to `date` and switched to all-day or timed. An all-day item is stored at the
    /// start of its day. Switching between all-day and timed drops `end` (a timed range makes no
    /// sense as all-day and vice versa); an event that keeps its kind keeps its duration, as
    /// `settingStart(_:)` does. Every other field is left untouched.
    public func rescheduled(to date: Date, allDay: Bool) -> Event {
        var copy = settingStart(FormFields.normalizedStart(date, allDay: allDay))
        if allDay != isAllDay { copy.end = nil }
        copy.isAllDay = allDay
        return copy
    }

    /// A copy scheduled the way the add/edit form describes it. An all-day item follows
    /// `rescheduled(to:allDay:)` (`end` is ignored: it keeps its own end, shifted with the start,
    /// or drops it when switching from timed). A timed item takes `start` and `end` (nil = no
    /// end) exactly as given. Every other field is left untouched.
    public func scheduled(start: Date, end: Date?, allDay: Bool) -> Event {
        if allDay { return rescheduled(to: start, allDay: true) }
        var copy = self
        copy.start = start
        copy.end = end
        copy.isAllDay = false
        return copy
    }
}
