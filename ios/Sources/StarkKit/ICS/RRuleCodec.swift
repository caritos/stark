// ios/Sources/StarkKit/ICS/RRuleCodec.swift
import Foundation

public enum RRuleCodec {
    private static let dayCodes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
    private static let weekdayOnlyCodes = ["MO", "TU", "WE", "TH", "FR"]
    private static let weekendDayCodes = ["SA", "SU"]

    public static func encode(_ rule: RecurrenceRule) -> String {
        var parts = ["FREQ=\(rule.frequency.rawValue.uppercased())"]
        if rule.interval != 1 { parts.append("INTERVAL=\(rule.interval)") }

        // Plain weekly BYDAY (unchanged from before this plan) is independent of the
        // monthly/yearly positional-vs-plain-day-of-month branch below - a rule only ever
        // has one of byDay (weekly) or byPositionalDay/byMonthDay (monthly/yearly) set.
        if let byDay = rule.byDay, !byDay.isEmpty {
            parts.append("BYDAY=" + byDay.map { dayCodes[$0.rawValue] }.joined(separator: ","))
        }

        if let positionalDays = rule.byPositionalDay, !positionalDays.isEmpty {
            encodePositionalDays(positionalDays, into: &parts)
        } else if let byMonthDay = rule.byMonthDay, !byMonthDay.isEmpty {
            parts.append("BYMONTHDAY=" + byMonthDay.map(String.init).joined(separator: ","))
        }

        if let byMonth = rule.byMonth, !byMonth.isEmpty {
            parts.append("BYMONTH=" + byMonth.map { String($0.rawValue) }.joined(separator: ","))
        }
        if let count = rule.count { parts.append("COUNT=\(count)") }
        if let until = rule.until { parts.append("UNTIL=\(ICSDateFormat.format(until, allDay: true))") }
        return parts.joined(separator: ";")
    }

    private static func encodePositionalDays(_ positionalDays: [PositionalDay], into parts: inout [String]) {
        // A generic day-type (anyDay/weekdayOnly/weekendDay) is always the sole entry
        // in the list (enforced by the picker UI) - no mixing with specific weekdays.
        guard let first = positionalDays.first else { return }
        switch first.dayType {
        case .anyDay:
            // Only .last is ever paired with .anyDay (enforced by OnWeekPickerView) - any other
            // position would produce a positive BYMONTHDAY indistinguishable from a plain
            // byMonthDay rule on decode. .last's negative encoding is what makes it unambiguous.
            parts.append("BYMONTHDAY=\(first.position.rawValue)")
        case .weekdayOnly:
            parts.append("BYDAY=" + weekdayOnlyCodes.joined(separator: ","))
            parts.append("BYSETPOS=\(first.position.rawValue)")
        case .weekendDay:
            parts.append("BYDAY=" + weekendDayCodes.joined(separator: ","))
            parts.append("BYSETPOS=\(first.position.rawValue)")
        case .weekday:
            let entries = positionalDays.compactMap { entry -> String? in
                guard case .weekday(let w) = entry.dayType else { return nil }
                return "\(entry.position.rawValue)\(dayCodes[w.rawValue])"
            }
            parts.append("BYDAY=" + entries.joined(separator: ","))
        }
    }

    public static func decode(_ value: String) -> RecurrenceRule? {
        var frequency: RecurrenceRule.Frequency?
        var interval = 1
        var byMonthDayRaw: [Int]?
        var byMonth: [Month]?
        var byDayRaw: [String]?
        var bySetPos: Int?
        var count: Int?
        var until: Date?

        for pair in value.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "FREQ": frequency = RecurrenceRule.Frequency(rawValue: kv[1].lowercased())
            case "INTERVAL": interval = Int(kv[1]) ?? 1
            case "BYDAY": byDayRaw = kv[1].split(separator: ",").map(String.init)
            case "BYMONTHDAY": byMonthDayRaw = kv[1].split(separator: ",").compactMap { Int($0) }
            case "BYMONTH": byMonth = kv[1].split(separator: ",").compactMap { Int($0).flatMap(Month.init) }
            case "BYSETPOS": bySetPos = Int(kv[1])
            case "COUNT": count = Int(kv[1])
            case "UNTIL": until = ICSDateFormat.parse(String(kv[1]))?.date
            default: break
            }
        }
        guard let frequency else { return nil }

        let (byPositionalDay, byMonthDay) = decodeDaySpecifier(byDayRaw: byDayRaw, byMonthDayRaw: byMonthDayRaw, bySetPos: bySetPos)

        return RecurrenceRule(
            frequency: frequency, interval: interval,
            byDay: frequency == .weekly ? byDayRaw?.compactMap { dayCodes.firstIndex(of: $0).flatMap(Weekday.init) } : nil,
            byMonthDay: byMonthDay, byPositionalDay: byPositionalDay, byMonth: byMonth,
            count: count, until: until
        )
    }

    private static func decodeDaySpecifier(byDayRaw: [String]?, byMonthDayRaw: [Int]?, bySetPos: Int?) -> (positional: [PositionalDay]?, monthDay: [Int]?) {
        // Ordinal BYDAY (e.g. "2TU", "-1FR") with no BYSETPOS: specific-weekday positional entries.
        if let byDayRaw, bySetPos == nil, byDayRaw.allSatisfy({ $0.count > 2 }) {
            let entries = byDayRaw.compactMap { token -> PositionalDay? in
                let code = String(token.suffix(2))
                let ordinalString = String(token.dropLast(2))
                guard let weekdayIndex = dayCodes.firstIndex(of: code),
                      let ordinal = Int(ordinalString),
                      let position = Position(rawValue: ordinal) else { return nil }
                return PositionalDay(position: position, dayType: .weekday(Weekday(rawValue: weekdayIndex)!))
            }
            return (entries, nil)
        }
        // BYDAY + BYSETPOS: a generic day-type positional entry.
        if let byDayRaw, let bySetPos, let position = Position(rawValue: bySetPos) {
            let dayType: DayTypeOrWeekday
            if Set(byDayRaw) == Set(weekdayOnlyCodes) { dayType = .weekdayOnly }
            else if Set(byDayRaw) == Set(weekendDayCodes) { dayType = .weekendDay }
            else { return (nil, byMonthDayRaw) }
            return ([PositionalDay(position: position, dayType: dayType)], nil)
        }
        // A single negative BYMONTHDAY with no BYDAY: an anyDay positional entry.
        if let byMonthDayRaw, byMonthDayRaw.count == 1, let position = Position(rawValue: byMonthDayRaw[0]), position == .last || byMonthDayRaw[0] < 0 {
            return ([PositionalDay(position: position, dayType: .anyDay)], nil)
        }
        return (nil, byMonthDayRaw)
    }
}
