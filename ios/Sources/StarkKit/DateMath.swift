import Foundation

/// Dates as "YYYY-MM-DD" strings; month0 is 0-based (January == 0).
public enum DateMath {
    private static func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }

    public static func components(_ iso: String) -> (year: Int, month0: Int, day: Int) {
        let parts = iso.split(separator: "-")
        return (Int(parts[0])!, Int(parts[1])! - 1, Int(parts[2])!)
    }

    public static func isoDate(year: Int, month0: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month0 + 1, day)
    }

    public static func date(from iso: String) -> Date {
        let c = components(iso)
        return calendar().date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: 12))!
    }

    public static func isoDate(from date: Date) -> String {
        let c = calendar().dateComponents([.year, .month, .day], from: date)
        return isoDate(year: c.year!, month0: c.month! - 1, day: c.day!)
    }

    public static func addDays(_ iso: String, _ n: Int) -> String {
        let next = calendar().date(byAdding: .day, value: n, to: date(from: iso))!
        return isoDate(from: next)
    }

    public static func daysInMonth(year: Int, month0: Int) -> Int {
        let d = calendar().date(from: DateComponents(year: year, month: month0 + 1, day: 1))!
        return calendar().range(of: .day, in: .month, for: d)!.count
    }

    /// 0 = Sunday ... 6 = Saturday.
    public static func weekday(year: Int, month0: Int, day: Int) -> Int {
        let d = calendar().date(from: DateComponents(year: year, month: month0 + 1, day: day, hour: 12))!
        return calendar().component(.weekday, from: d) - 1
    }
}

public struct YearMonth: Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month0: Int

    public init(year: Int, month0: Int) {
        // Normalize an out-of-range month0 (e.g. -1 or 12, from a ±1 offset) into a real month/year.
        let normalized = ((month0 % 12) + 12) % 12
        let yearOffset = (month0 - normalized) / 12
        self.year = year + yearOffset
        self.month0 = normalized
    }

    public init(date: Date) {
        let c = DateMath.components(DateMath.isoDate(from: date))
        self.year = c.year
        self.month0 = c.month0
    }

    public var fileName: String {
        String(format: "%04d-%02d.ics", year, month0 + 1)
    }

    public var description: String { fileName }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month0) < (rhs.year, rhs.month0)
    }
}
