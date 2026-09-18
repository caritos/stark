public enum Position: Int, Codable, Equatable, Hashable, Sendable {
    case first = 1, second, third, fourth
    case last = -1
}

public enum DayTypeOrWeekday: Codable, Equatable, Hashable, Sendable {
    case weekday(Weekday)
    case anyDay
    case weekdayOnly
    case weekendDay
}

public struct PositionalDay: Equatable, Codable, Hashable, Sendable {
    public var position: Position
    public var dayType: DayTypeOrWeekday

    public init(position: Position, dayType: DayTypeOrWeekday) {
        self.position = position
        self.dayType = dayType
    }
}
