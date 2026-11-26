import Foundation

/// The date the round and corner watch complications show. The day names are the owner's own
/// short forms ("Tues", "Thurs"), so they are not taken from the locale.
public struct WatchDateFace: Equatable, Sendable {
    public let weekday: String
    public let day: String
    public let accessibilityLabel: String

    private static let short = ["Sun", "Mon", "Tues", "Wed", "Thurs", "Fri", "Sat"]
    private static let full = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    public init(date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) {
        let index = calendar.component(.weekday, from: date) - 1
        weekday = Self.short[index]
        day = String(calendar.component(.day, from: date))
        accessibilityLabel = "\(Self.full[index]) \(day)"
    }

    /// `entryDates` plus the next seven midnights, so the date turns over even if watchOS is late
    /// asking for a new timeline.
    public static func timelineDates(_ entryDates: [Date], now: Date,
                                     calendar: Calendar = Calendar(identifier: .gregorian)) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let midnights = (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        return Set(entryDates + midnights).sorted()
    }
}
