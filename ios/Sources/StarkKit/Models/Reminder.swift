import Foundation

// Named `Reminder`, not `Task` — `Task` is Swift's own concurrency type.
public struct Reminder: Equatable, Codable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    public var isCompleted: Bool
    public var completedDate: Date?
    public var priority: Int?
    public var recurrence: RecurrenceRule?
    public var exceptionDates: [Date]
    /// When the user actually ticked it done (`completedDate` stays the due occurrence).
    public var completedAt: Date?
    /// For a completed copy of a recurring reminder: the master's id.
    public var seriesID: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completedDate: Date? = nil,
        priority: Int? = nil,
        recurrence: RecurrenceRule? = nil,
        exceptionDates: [Date] = [],
        completedAt: Date? = nil,
        seriesID: String? = nil
    ) {
        self.completedAt = completedAt
        self.seriesID = seriesID
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedDate = completedDate
        self.priority = priority
        self.recurrence = recurrence
        self.exceptionDates = exceptionDates
    }
}
