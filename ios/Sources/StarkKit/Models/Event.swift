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
}
