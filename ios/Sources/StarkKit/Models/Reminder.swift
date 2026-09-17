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

    public init(
        id: String = UUID().uuidString,
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completedDate: Date? = nil,
        priority: Int? = nil,
        recurrence: RecurrenceRule? = nil,
        exceptionDates: [Date] = []
    ) {
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
