// ios/Sources/StarkKit/Planner/CalendarViewMenu.swift

/// The choices in the calendar's view menu, in menu order. DayTicker covers the week and
/// month modes; Month is the full-screen month grid.
public enum CalendarViewChoice: CaseIterable, Equatable, Sendable {
    case dayTicker, month, year

    public var title: String {
        switch self {
        case .dayTicker: return "DayTicker"
        case .month: return "Month"
        case .year: return "Year"
        }
    }

    public var systemImage: String {
        switch self {
        case .dayTicker: return "calendar.day.timeline.left"
        case .month: return "square.grid.3x3"
        case .year: return "calendar"
        }
    }
}

public enum CalendarViewMenu {
    /// The menu choice that matches the screen: the full month wins, then year mode.
    public static func current(for mode: CalendarMode, fullMonth: Bool) -> CalendarViewChoice {
        if fullMonth { return .month }
        return mode == .year ? .year : .dayTicker
    }

    /// The mode and full-month flag after picking `choice`. Month keeps the mode (year becomes month, which it would cover); Year opens
    /// year; DayTicker leaves year for the month strip and keeps week or month as they are.
    public static func target(
        after choice: CalendarViewChoice, current mode: CalendarMode
    ) -> (mode: CalendarMode, fullMonth: Bool) {
        switch choice {
        case .month: return (mode == .year ? .month : mode, true)
        case .year: return (.year, false)
        case .dayTicker: return (mode == .year ? .month : mode, false)
        }
    }

    /// What VoiceOver reads as the menu button's value.
    public static func accessibilityValue(for mode: CalendarMode, fullMonth: Bool) -> String {
        current(for: mode, fullMonth: fullMonth).title
    }
}
