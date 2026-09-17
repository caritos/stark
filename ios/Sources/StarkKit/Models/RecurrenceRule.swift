import Foundation

public struct RecurrenceRule: Equatable, Codable, Sendable {
    public enum Frequency: String, Codable, Equatable, Sendable {
        case daily, weekly, monthly, yearly
    }

    public var frequency: Frequency
    public var interval: Int
    public var byDay: [Weekday]?
    public var byMonthDay: Int?
    public var count: Int?
    public var until: Date?

    public init(
        frequency: Frequency,
        interval: Int = 1,
        byDay: [Weekday]? = nil,
        byMonthDay: Int? = nil,
        count: Int? = nil,
        until: Date? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.byDay = byDay
        self.byMonthDay = byMonthDay
        self.count = count
        self.until = until
    }
}
