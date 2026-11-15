// ios/Sources/StarkKit/Items/RecurrenceDescriptor.swift
import Foundation

/// A repeat rule in EventKit's vocabulary, without importing EventKit. The fields mirror
/// `EKRecurrenceRule` one to one (frequency, interval, days of the week with an optional week
/// number each, days of the month, months of the year, set positions, end) so the app-side
/// mapping is a thin copy. `init(_ rule:)` turns Stark's rule into a descriptor; `asStarkRule()`
/// turns one read from Apple back, throwing `ItemRepositoryError.unrepresentable` with a readable
/// reason for every Apple shape Stark cannot hold.
///
/// Conventions (from the EventKit write spikes, section (d)):
/// - The first date (start or due) always counts as an occurrence even when it does not match the
///   rule, in EventKit and in Stark's `OccurrenceExpander` alike, so no code adjusts for it.
/// - `end: .until(date)` is the INCLUSIVE last day, as the start of that day (Stark's date-only
///   `UNTIL`). The app-side EventKit mapping writes it as 23:59:59 local on that day (a start-of-day
///   `EKRecurrenceEnd` would lose the last occurrence of a timed item) and reads an all-day event's
///   end as its UTC calendar day.
/// - Monthly day 29-31: EventKit skips months that lack the day, but Stark's `OccurrenceExpander`
///   clamps to the last day (`min(day, daysInMonth)`). After the move to Apple, Apple's skipping is
///   the truth; the picker's "Last day of the month" is the clamp case.
/// - "Last day of the month" is written as `daysOfTheMonth [-1]`; both that and "all seven weekdays
///   with set position -1" read back as Stark's positional last day. A bare `byMonthDay [-1]` rule
///   therefore comes back as the equivalent positional form.
public struct RecurrenceDescriptor: Equatable, Sendable {
    public enum Frequency: Equatable, Sendable { case daily, weekly, monthly, yearly }

    public enum End: Equatable, Sendable {
        case never
        /// The inclusive last day, as the start of that day.
        case until(Date)
        case count(Int)
    }

    /// A weekday with an optional week number (`EKRecurrenceDayOfWeek`): 2 = second, -1 = last.
    public struct DayOfWeek: Equatable, Hashable, Sendable {
        public var weekday: Weekday
        public var weekNumber: Int?

        public init(_ weekday: Weekday, weekNumber: Int? = nil) {
            self.weekday = weekday
            self.weekNumber = weekNumber
        }
    }

    public var frequency: Frequency
    public var interval: Int
    public var daysOfTheWeek: [DayOfWeek]
    /// 1...31, or -1 for the last day.
    public var daysOfTheMonth: [Int]
    /// 1...12.
    public var monthsOfTheYear: [Int]
    public var setPositions: [Int]
    public var end: End

    public init(frequency: Frequency, interval: Int = 1, daysOfTheWeek: [DayOfWeek] = [],
                daysOfTheMonth: [Int] = [], monthsOfTheYear: [Int] = [], setPositions: [Int] = [],
                end: End = .never) {
        self.frequency = frequency
        self.interval = interval
        self.daysOfTheWeek = daysOfTheWeek
        self.daysOfTheMonth = daysOfTheMonth
        self.monthsOfTheYear = monthsOfTheYear
        self.setPositions = setPositions
        self.end = end
    }

    private static let weekdaysMonToFri: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
    private static let weekendDays: [Weekday] = [.saturday, .sunday]

    // MARK: Stark -> descriptor

    /// Throws `unrepresentable` only for a rule no Apple repeat can express (an interval below 1, a
    /// count below 1, or a positional list mixing generic day types with specific weekdays).
    public init(_ rule: RecurrenceRule) throws {
        guard rule.interval >= 1 else {
            throw ItemRepositoryError.unrepresentable("The repeat interval must be at least 1.")
        }
        let frequency: Frequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        var days: [DayOfWeek] = []
        var monthDays = rule.byMonthDay ?? []
        var positions: [Int] = []

        if let byDay = rule.byDay, !byDay.isEmpty {
            days = byDay.map { DayOfWeek($0) }
        } else if let positional = rule.byPositionalDay, let first = positional.first {
            switch first.dayType {
            case .weekday:
                days = try positional.map { entry in
                    guard case .weekday(let weekday) = entry.dayType else { throw Self.mixedPositional }
                    return DayOfWeek(weekday, weekNumber: entry.position.rawValue)
                }
                monthDays = []
            case .anyDay, .weekdayOnly, .weekendDay:
                guard positional.allSatisfy({ $0.dayType == first.dayType }) else { throw Self.mixedPositional }
                let numbers = positional.map(\.position.rawValue)
                switch first.dayType {
                case .anyDay:
                    monthDays = numbers
                case .weekdayOnly:
                    days = Self.weekdaysMonToFri.map { DayOfWeek($0) }
                    positions = numbers
                    monthDays = []
                default:
                    days = Self.weekendDays.map { DayOfWeek($0) }
                    positions = numbers
                    monthDays = []
                }
            }
        }

        var end = End.never
        if let until = rule.until {
            end = .until(Calendar(identifier: .gregorian).startOfDay(for: until))
        } else if let count = rule.count {
            guard count >= 1 else { throw ItemRepositoryError.unrepresentable("The repeat count must be at least 1.") }
            end = .count(count)
        }

        self.init(frequency: frequency, interval: rule.interval, daysOfTheWeek: days,
                  daysOfTheMonth: monthDays, monthsOfTheYear: (rule.byMonth ?? []).map(\.rawValue),
                  setPositions: positions, end: end)
    }

    private static var mixedPositional: ItemRepositoryError {
        .unrepresentable("A repeat that mixes day types (for example the last weekday and a named weekday) cannot be saved to Apple.")
    }

    // MARK: descriptor -> Stark

    /// True when `asStarkRule()` succeeds; the edit sheet's `hasUnrepresentableRepeat` is its negation.
    public var isRepresentableInStark: Bool { (try? asStarkRule()) != nil }

    public func asStarkRule() throws -> RecurrenceRule {
        func fail(_ reason: String) -> ItemRepositoryError { .unrepresentable(reason) }

        guard interval >= 1 else { throw fail("The repeat interval must be at least 1.") }

        var rule = RecurrenceRule(frequency: {
            switch frequency {
            case .daily: return .daily
            case .weekly: return .weekly
            case .monthly: return .monthly
            case .yearly: return .yearly
            }
        }(), interval: interval)

        switch end {
        case .never: break
        case .until(let date): rule.until = Calendar(identifier: .gregorian).startOfDay(for: date)
        case .count(let count):
            guard count >= 1 else { throw fail("The repeat count must be at least 1.") }
            rule.count = count
        }

        if !monthsOfTheYear.isEmpty {
            guard frequency == .yearly else { throw fail("Stark supports months of the year only on yearly repeats.") }
            rule.byMonth = try monthsOfTheYear.map { number in
                guard let month = Month(rawValue: number) else { throw fail("The repeat names month \(number), which does not exist.") }
                return month
            }
        }

        let numbered = daysOfTheWeek.filter { $0.weekNumber != nil }
        guard numbered.isEmpty || numbered.count == daysOfTheWeek.count else {
            throw fail("Apple repeats on some weekdays every week and on others in a particular week of the month, which Stark cannot hold.")
        }

        if !daysOfTheWeek.isEmpty {
            guard daysOfTheMonth.isEmpty else {
                throw fail("Apple repeats on both days of the week and days of the month, which Stark cannot hold.")
            }
            switch frequency {
            case .daily:
                throw fail("Stark cannot restrict a daily repeat to certain weekdays.")
            case .weekly:
                guard numbered.isEmpty, setPositions.isEmpty else {
                    throw fail("Stark cannot use week numbers or set positions on a weekly repeat.")
                }
                rule.byDay = daysOfTheWeek.map(\.weekday)
            case .monthly, .yearly:
                rule.byPositionalDay = numbered.isEmpty ? try positionalFromSetPositions() : try positionalFromWeekNumbers()
            }
            return rule
        }

        guard setPositions.isEmpty else {
            throw fail("Apple repeats on set positions without naming the days, which Stark cannot hold.")
        }
        if !daysOfTheMonth.isEmpty {
            guard frequency == .monthly || frequency == .yearly else {
                throw fail("Stark supports days of the month only on monthly and yearly repeats.")
            }
            guard daysOfTheMonth.allSatisfy({ (1...31).contains($0) || $0 == -1 }) else {
                throw fail("Stark supports days of the month 1 to 31 and the last day only.")
            }
            if daysOfTheMonth == [-1] {
                rule.byPositionalDay = [PositionalDay(position: .last, dayType: .anyDay)]
            } else {
                rule.byMonthDay = daysOfTheMonth
            }
        }
        return rule
    }

    private func position(_ number: Int) throws -> Position {
        guard let position = Position(rawValue: number) else {
            throw ItemRepositoryError.unrepresentable("Stark supports the 1st to 4th and the last week of the month; Apple's repeat uses \(number).")
        }
        return position
    }

    /// `2TU`, `-1FR`, `1MO,3MO`: week numbers on the weekdays. Every weekday must repeat in the same
    /// weeks, so "1st Monday and 3rd Wednesday" is refused.
    private func positionalFromWeekNumbers() throws -> [PositionalDay] {
        guard setPositions.isEmpty else {
            throw ItemRepositoryError.unrepresentable("Stark cannot combine week numbers with set positions.")
        }
        var byWeekday: [Weekday: Set<Int>] = [:]
        for entry in daysOfTheWeek { byWeekday[entry.weekday, default: []].insert(entry.weekNumber!) }
        guard Set(byWeekday.values).count == 1 else {
            throw ItemRepositoryError.unrepresentable("Apple repeats on different weeks for different weekdays (for example 1st Monday and 3rd Wednesday), which Stark cannot hold.")
        }
        return try daysOfTheWeek.map { entry in
            PositionalDay(position: try position(entry.weekNumber!), dayType: .weekday(entry.weekday))
        }
    }

    /// Weekdays plus set positions: the last weekday, the first weekend day, the last day (all seven
    /// days), or named weekdays at the listed positions.
    private func positionalFromSetPositions() throws -> [PositionalDay] {
        guard !setPositions.isEmpty else {
            throw ItemRepositoryError.unrepresentable("Apple repeats on every listed weekday of the month, which Stark cannot hold.")
        }
        let positions = try setPositions.map { try position($0) }
        let weekdays = Set(daysOfTheWeek.map(\.weekday))
        if weekdays == Set(Self.weekdaysMonToFri) {
            return positions.map { PositionalDay(position: $0, dayType: .weekdayOnly) }
        }
        if weekdays == Set(Self.weekendDays) {
            return positions.map { PositionalDay(position: $0, dayType: .weekendDay) }
        }
        if weekdays.count == 7 {
            guard positions.allSatisfy({ $0 == .last }) else {
                throw ItemRepositoryError.unrepresentable("Stark supports only the last day of the month for an every-day repeat with set positions.")
            }
            return [PositionalDay(position: .last, dayType: .anyDay)]
        }
        var seen = Set<Weekday>()
        return daysOfTheWeek.map(\.weekday).filter { seen.insert($0).inserted }.flatMap { weekday in
            positions.map { PositionalDay(position: $0, dayType: .weekday(weekday)) }
        }
    }
}

/// Stark's priority is iCal 1-9 (nil = none); `EKReminder.priority` is 0-9 with 0 = none. The two
/// scales agree on 1-9; anything outside means none.
public func appleReminderPriority(_ icalPriority: Int?) -> Int {
    guard let icalPriority, (1...9).contains(icalPriority) else { return 0 }
    return icalPriority
}

public func icalPriority(fromApple priority: Int) -> Int? {
    (1...9).contains(priority) ? priority : nil
}
