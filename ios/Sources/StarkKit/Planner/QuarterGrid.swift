// ios/Sources/StarkKit/Planner/QuarterGrid.swift
import Foundation

/// Which edges of a quarter cell sit on a month boundary (drawn as a thicker seam line).
public struct QuarterSeam: Equatable, Sendable {
    /// The cell directly above belongs to a different month.
    public let top: Bool
    /// The cell to the left (same row) belongs to a different month.
    public let leading: Bool

    public init(top: Bool, leading: Bool) {
        self.top = top
        self.leading = leading
    }
}

/// The cells of the full-screen Quarter: 13 Sunday-first weeks starting at the Sunday on or before
/// the 1st of the displayed month (Fantastical's "Start Quarter View On: First Week of Month").
/// Every cell counts as in range (`isInMonth` is true): the quarter has no dimmed days.
public enum QuarterGrid {
    public static let weekCount = 13
    public static let dayCount = weekCount * 7

    public static func days(startingAt month: YearMonth) -> [GridDay] {
        let leading = DateMath.weekday(year: month.year, month0: month.month0, day: 1)
        let firstOfMonth = DateMath.isoDate(year: month.year, month0: month.month0, day: 1)
        return (0..<dayCount).map { index in
            let c = DateMath.components(DateMath.addDays(firstOfMonth, index - leading))
            return GridDay(year: c.year, month0: c.month0, day: c.day, isInMonth: true)
        }
    }

    /// Everything the quarter shows, from the start of the first cell's day to the last second of
    /// the last cell's day. Same contract as `MonthGrid.range(for:calendar:)` (the calendar must
    /// share the current time zone).
    public static func range(
        for month: YearMonth,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> ClosedRange<Date> {
        let cells = days(startingAt: month)
        let first = calendar.startOfDay(for: cells[0].date)
        let lastStart = calendar.startOfDay(for: cells[cells.count - 1].date)
        let dayAfterLast = calendar.date(byAdding: .day, value: 1, to: lastStart)
            ?? lastStart.addingTimeInterval(86_400)
        return first...dayAfterLast.addingTimeInterval(-1)
    }

    /// The header title's two ends, e.g. ("Nov 2026", "Jan 2027"): the displayed month and the
    /// month two after it. The view colours each year red.
    public static func title(for month: YearMonth) -> (first: String, second: String) {
        let last = YearMonth(year: month.year, month0: month.month0 + 2)
        return (monthYear(month), monthYear(last))
    }

    /// Indexes of every 1st of a month in `days`.
    public static func monthStarts(in days: [GridDay]) -> [Int] {
        days.indices.filter { days[$0].day == 1 }
    }

    /// The grey pill text for the 1st of a month ("Nov 1"); nil for other days.
    public static func monthStartLabel(for day: GridDay) -> String? {
        guard day.day == 1 else { return nil }
        return "\(shortMonth(day.month0)) 1"
    }

    /// Month-boundary edges of the cell at `index` in a Sunday-first grid of `days`.
    public static func seam(at index: Int, in days: [GridDay]) -> QuarterSeam {
        guard days.indices.contains(index) else { return QuarterSeam(top: false, leading: false) }
        func differs(_ other: Int) -> Bool {
            days[other].year != days[index].year || days[other].month0 != days[index].month0
        }
        let top = index >= 7 && differs(index - 7)
        let leading = index % 7 != 0 && differs(index - 1)
        return QuarterSeam(top: top, leading: leading)
    }

    // English abbreviations, like the rest of the app's fixed-format dates (en_US_POSIX "MMM").
    private static let monthAbbreviations = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static func shortMonth(_ month0: Int) -> String { monthAbbreviations[month0] }
    private static func monthYear(_ m: YearMonth) -> String { "\(shortMonth(m.month0)) \(m.year)" }
}
