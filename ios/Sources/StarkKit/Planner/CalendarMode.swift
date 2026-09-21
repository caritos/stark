// ios/Sources/StarkKit/Planner/CalendarMode.swift

/// How much calendar the screen shows, smallest to largest: one week row, the month grid (with
/// the agenda below), or a whole year. A drag bar between grid and agenda moves between them.
public enum CalendarMode: Equatable, Sendable {
    case week, month, year

    /// The next larger mode (drag down), or nil at the largest.
    public var expanded: CalendarMode? {
        switch self {
        case .week: return .month
        case .month: return .year
        case .year: return nil
        }
    }

    /// The next smaller mode (drag up), or nil at the smallest.
    public var collapsed: CalendarMode? {
        switch self {
        case .year: return .month
        case .month: return .week
        case .week: return nil
        }
    }

    /// What VoiceOver reads as the drag bar's value.
    public var title: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }

    /// Points of vertical travel on release that count as a deliberate drag.
    public static let dragThreshold: Double = 30
    /// Predicted travel (points) that makes a short, fast fling count.
    public static let flingThreshold: Double = 100

    /// The mode after a vertical drag on the bar ends. `translation` is the travel so far and
    /// `predictedEnd` where the gesture would have coasted to (both positive = down). Down
    /// expands, up collapses; a drag past an end mode changes nothing. Travel of at least
    /// `dragThreshold` decides; otherwise a predicted travel of at least `flingThreshold` does;
    /// otherwise nothing changes.
    public func afterDrag(translation: Double, predictedEnd: Double) -> CalendarMode {
        let travel: Double
        if abs(translation) >= Self.dragThreshold {
            travel = translation
        } else if abs(predictedEnd) >= Self.flingThreshold {
            travel = predictedEnd
        } else {
            return self
        }
        return (travel > 0 ? expanded : collapsed) ?? self
    }
}
