import Foundation

/// Text for an agenda row placed by a timeboxing plan: the planned range as the primary time
/// line, and the original due (overdue label, or a timed task's own time) as a secondary line.
public enum PlanRowText {
    public struct Lines: Equatable, Sendable {
        public let primary: String
        public let secondary: String?
    }

    /// - Parameters:
    ///   - overdueText: the existing overdue label ("Sep 19 at 6:00 AM - 3 days overdue") for an
    ///     overdue row, else nil.
    ///   - time: the app's time formatter (12/24-hour as the user's locale says).
    public static func make(occurrence: Date, overdueText: String?, range: ClosedRange<Date>,
                            time: (Date) -> String,
                            calendar: Calendar = Calendar(identifier: .gregorian)) -> Lines {
        var start = time(range.lowerBound)
        let end = time(range.upperBound)
        // Write a shared trailing "AM"/"PM" once, as event ranges do.
        if let s = start.lastIndex(of: " "), let e = end.lastIndex(of: " "),
           start[start.index(after: s)...] == end[end.index(after: e)...],
           !start[start.index(after: s)...].contains(where: \.isNumber) {
            start = String(start[..<s])
        }
        var secondary: String?
        if let overdueText {
            secondary = overdueText
        } else if calendar.startOfDay(for: occurrence) != occurrence {
            secondary = "due \(time(occurrence))"
        }
        return Lines(primary: "\(start) - \(end)", secondary: secondary)
    }
}
