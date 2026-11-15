import Foundation

/// `stark-claude today`: unavailable until the Mac tool exists (spec decision 4).
///
/// It used to pull the app's `/Documents` and read Stark's `.ics` files. Stark now creates items in
/// Apple Calendar and Reminders, which that copy does not contain, so the old answer would silently
/// leave them out. The pulling version is in git history (before the Apple write path, phase 1).
/// It runs nothing and reads nothing; the caller prints the text and exits 0.
public struct TodayCommand {
    public static let unavailable = """
    stark-claude today is unavailable until the Mac tool: Stark now keeps items in Apple Calendar \
    and Reminders, which this command cannot read. Check the day in Stark on the phone.
    """

    public init() {}

    /// Parses `yyyy-MM-dd` in this Mac's calendar and time zone (still checked, so a typo is
    /// reported the same way as before).
    public static func parseDay(_ text: String, calendar: Calendar = Calendar(identifier: .gregorian)) throws -> Date {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: y, month: m, day: d)),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: y, month: m, day: d)
        else { throw CLIError.badRequest("--date must be a real date like 2026-11-07 (got \"\(text.prefix(40))\")") }
        return calendar.startOfDay(for: date)
    }

    public func run(day: Date?) -> String {
        Self.unavailable
    }
}
