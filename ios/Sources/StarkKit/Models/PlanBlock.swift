import Foundation

/// A slice of a day reserved for working on one reminder occurrence (timeboxing).
public struct PlanBlock: Equatable, Codable, Identifiable, Sendable {
    public var id: String
    public var reminderID: String
    /// The reminder occurrence this block plans (a recurring series has many).
    public var occurrence: Date
    public var start: Date
    public var minutes: Int

    public init(id: String = UUID().uuidString, reminderID: String, occurrence: Date, start: Date, minutes: Int) {
        self.id = id
        self.reminderID = reminderID
        self.occurrence = occurrence
        self.start = start
        self.minutes = minutes
    }

    public var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }
}
