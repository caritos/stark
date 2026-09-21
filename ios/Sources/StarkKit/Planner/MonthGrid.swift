// ios/Sources/StarkKit/Planner/MonthGrid.swift
import Foundation

/// One cell of the month grid: a real calendar date, flagged with whether it belongs to the month
/// being shown (the others are the neighbouring months' leading/trailing days).
public struct GridDay: Hashable, Sendable, Identifiable {
    public let year: Int
    public let month0: Int
    public let day: Int
    public let isInMonth: Bool

    public init(year: Int, month0: Int, day: Int, isInMonth: Bool) {
        self.year = year
        self.month0 = month0
        self.day = day
        self.isInMonth = isInMonth
    }

    /// `yyyy-MM-dd`.
    public var iso: String { DateMath.isoDate(year: year, month0: month0, day: day) }
    public var id: String { iso }
    /// Local noon of this day (`DateMath.date(from:)`), the app's usual "a day" timestamp.
    public var date: Date { DateMath.date(from: iso) }
}

/// The cells of a Sunday-first month grid. Always 6 rows x 7 columns = 42 cells, so the grid (and
/// the agenda below it) never resizes as the user pages between months.
public enum MonthGrid {
    public static let dayCount = 42

    public static func days(for month: YearMonth) -> [GridDay] {
        // DateMath.weekday: 0 = Sunday ... 6 = Saturday, i.e. how many cells precede day 1.
        let leading = DateMath.weekday(year: month.year, month0: month.month0, day: 1)
        let firstOfMonth = DateMath.isoDate(year: month.year, month0: month.month0, day: 1)
        return (0..<dayCount).map { index in
            let c = DateMath.components(DateMath.addDays(firstOfMonth, index - leading))
            return GridDay(
                year: c.year,
                month0: c.month0,
                day: c.day,
                isInMonth: c.year == month.year && c.month0 == month.month0
            )
        }
    }

    /// Everything the grid shows: from the start of the first cell's day to the last second of the
    /// last cell's day. Stepped with `calendar`, never by 86 400 seconds, so DST days are right.
    public static func range(
        for month: YearMonth,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> ClosedRange<Date> {
        let cells = days(for: month)
        let first = calendar.startOfDay(for: cells[0].date)
        let lastStart = calendar.startOfDay(for: cells[cells.count - 1].date)
        let dayAfterLast = calendar.date(byAdding: .day, value: 1, to: lastStart) ?? lastStart.addingTimeInterval(86_400)
        return first...dayAfterLast.addingTimeInterval(-1)
    }
}
