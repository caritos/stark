// ios/Sources/StarkKit/Planner/CalendarViewMenu.swift

/// The choices in the calendar's view menu. DayTicker covers the week and month modes.
public enum CalendarViewChoice: CaseIterable, Equatable, Sendable {
    case dayTicker, year

    public var title: String {
        switch self {
        case .dayTicker: return "DayTicker"
        case .year: return "Year"
        }
    }

    public var systemImage: String {
        switch self {
        case .dayTicker: return "calendar.day.timeline.left"
        case .year: return "calendar"
        }
    }
}

public enum CalendarViewMenu {
    /// The menu choice that matches a mode.
    public static func current(for mode: CalendarMode) -> CalendarViewChoice {
        mode == .year ? .year : .dayTicker
    }

    /// The mode after picking `choice`: Year opens year; DayTicker leaves year for the month
    /// grid and keeps week or month as they are.
    public static func mode(after choice: CalendarViewChoice, current: CalendarMode) -> CalendarMode {
        switch choice {
        case .year: return .year
        case .dayTicker: return current == .year ? .month : current
        }
    }

    /// What VoiceOver reads as the menu button's value.
    public static func accessibilityValue(for mode: CalendarMode) -> String {
        current(for: mode).title
    }
}
