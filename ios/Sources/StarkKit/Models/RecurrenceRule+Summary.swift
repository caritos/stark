// ios/Sources/StarkKit/Models/RecurrenceRule+Summary.swift
import Foundation

extension RecurrenceRule {
    /// A human-readable description of the full rule (not just frequency+interval), e.g.
    /// "Every month on the 2nd Tuesday" or "Every year in March, September". Used by the
    /// "Repeat" row summary in both AddItemView and CustomRepeatView so a custom rule never
    /// shows a misleadingly generic "Every Month" when it actually carries day/month/positional
    /// specifics.
    public var summary: String {
        var result = "Every \(interval == 1 ? "" : "\(interval) ")\(unitLabel)\(interval == 1 ? "" : "s")"

        if frequency == .weekly, let byDay, !byDay.isEmpty {
            let names = byDay.sorted { $0.rawValue < $1.rawValue }.map(Self.weekdayName)
            result += " on \(names.joined(separator: ", "))"
        }

        if frequency == .yearly, let byMonth, !byMonth.isEmpty {
            let names = byMonth.sorted { $0.rawValue < $1.rawValue }.map(Self.monthName)
            result += " in \(names.joined(separator: ", "))"
        }

        if frequency == .monthly || frequency == .yearly {
            if let byPositionalDay, !byPositionalDay.isEmpty {
                let descriptions = byPositionalDay.map(Self.positionalDayDescription)
                result += " on the \(descriptions.joined(separator: ", "))"
            } else if let byMonthDay, !byMonthDay.isEmpty {
                let ordinals = byMonthDay.sorted().map(Self.ordinal)
                result += " on the \(ordinals.joined(separator: ", "))"
            }
        }

        return result
    }

    private var unitLabel: String {
        switch frequency {
        case .daily: return "day"
        case .weekly: return "week"
        case .monthly: return "month"
        case .yearly: return "year"
        }
    }

    private static func weekdayName(_ day: Weekday) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][day.rawValue]
    }

    private static func monthName(_ month: Month) -> String {
        ["January", "February", "March", "April", "May", "June", "July", "August",
         "September", "October", "November", "December"][month.rawValue - 1]
    }

    private static func positionalDayDescription(_ positional: PositionalDay) -> String {
        let positionWord: String
        switch positional.position {
        case .first: positionWord = "1st"
        case .second: positionWord = "2nd"
        case .third: positionWord = "3rd"
        case .fourth: positionWord = "4th"
        case .last: positionWord = "last"
        }
        let dayWord: String
        switch positional.dayType {
        case .weekday(let w): dayWord = weekdayName(w)
        case .anyDay: dayWord = "day"
        case .weekdayOnly: dayWord = "weekday"
        case .weekendDay: dayWord = "weekend day"
        }
        return "\(positionWord) \(dayWord)"
    }

    /// Ordinal suffix for a day-of-month number. Handles the 11th/12th/13th exception
    /// correctly even though only 1st/2nd/3rd/4th are strictly required.
    private static func ordinal(_ n: Int) -> String {
        let remainder100 = n % 100
        if remainder100 >= 11 && remainder100 <= 13 { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }
}
