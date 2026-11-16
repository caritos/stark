// ios/Sources/StarkKit/Planner/CalendarViewMenu.swift

/// The choices in the calendar's view menu, in menu order. DayTicker covers the week and
/// month modes; Month and Quarter are the full-screen grids.
public enum CalendarViewChoice: CaseIterable, Equatable, Sendable {
    case dayTicker, day, week, month, quarter, year

    public var title: String {
        switch self {
        case .dayTicker: return "DayTicker"
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .quarter: return "Quarter"
        case .year: return "Year"
        }
    }

    public var systemImage: String {
        switch self {
        case .dayTicker: return "calendar.day.timeline.left"
        case .day: return "rectangle.portrait"
        case .week: return "rectangle.split.3x1"
        case .month: return "square.grid.3x3"
        case .quarter: return "rectangle.split.3x3"
        case .year: return "calendar"
        }
    }
}

/// Which full-screen calendar covers the DayTicker and agenda, if any.
public enum FullScreenCalendar: Equatable, Sendable {
    case none, day, week, month, quarter
}

public enum CalendarViewMenu {
    /// The menu choice that matches the screen: a full-screen calendar wins, then year mode.
    public static func current(for mode: CalendarMode, full: FullScreenCalendar) -> CalendarViewChoice {
        switch full {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .quarter: return .quarter
        case .none: return mode == .year ? .year : .dayTicker
        }
    }

    /// The mode and full-screen calendar after picking `choice`. Month and Quarter keep the mode
    /// (year becomes month, which they would cover); Year opens year; DayTicker leaves year for
    /// the month strip and keeps week or month as they are.
    public static func target(
        after choice: CalendarViewChoice, current mode: CalendarMode
    ) -> (mode: CalendarMode, full: FullScreenCalendar) {
        let underFull: CalendarMode = mode == .year ? .month : mode
        switch choice {
        case .day: return (underFull, .day)
        case .week: return (underFull, .week)
        case .month: return (underFull, .month)
        case .quarter: return (underFull, .quarter)
        case .year: return (.year, .none)
        case .dayTicker: return (underFull, .none)
        }
    }

    /// What VoiceOver reads as the menu button's value.
    public static func accessibilityValue(for mode: CalendarMode, full: FullScreenCalendar) -> String {
        current(for: mode, full: full).title
    }
}
