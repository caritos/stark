import Foundation

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

    public init(
        id: String = UUID().uuidString,
        title: String,
        notes: String? = nil,
        start: Date,
        end: Date? = nil,
        isAllDay: Bool = false,
        location: String? = nil,
        recurrence: RecurrenceRule? = nil,
        exceptionDates: [Date] = []
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
