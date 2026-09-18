import Foundation

public enum RRuleCodec {
    private static let dayCodes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]

    public static func encode(_ rule: RecurrenceRule) -> String {
        var parts = ["FREQ=\(rule.frequency.rawValue.uppercased())"]
        if rule.interval != 1 { parts.append("INTERVAL=\(rule.interval)") }
        if let byDay = rule.byDay, !byDay.isEmpty {
            parts.append("BYDAY=" + byDay.map { dayCodes[$0.rawValue] }.joined(separator: ","))
        }
        if let byMonthDay = rule.byMonthDay, !byMonthDay.isEmpty {
            parts.append("BYMONTHDAY=" + byMonthDay.map(String.init).joined(separator: ","))
        }
        if let count = rule.count { parts.append("COUNT=\(count)") }
        if let until = rule.until { parts.append("UNTIL=\(ICSDateFormat.format(until, allDay: true))") }
        return parts.joined(separator: ";")
    }

    public static func decode(_ value: String) -> RecurrenceRule? {
        var frequency: RecurrenceRule.Frequency?
        var interval = 1
        var byDay: [Weekday]?
        var byMonthDay: [Int]?
        var count: Int?
        var until: Date?

        for pair in value.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "FREQ": frequency = RecurrenceRule.Frequency(rawValue: kv[1].lowercased())
            case "INTERVAL": interval = Int(kv[1]) ?? 1
            case "BYDAY": byDay = kv[1].split(separator: ",").compactMap { code in
                dayCodes.firstIndex(of: String(code)).flatMap { Weekday(rawValue: $0) }
            }
            case "BYMONTHDAY": byMonthDay = kv[1].split(separator: ",").compactMap { Int($0) }
            case "COUNT": count = Int(kv[1])
            case "UNTIL": until = ICSDateFormat.parse(String(kv[1]))?.date
            default: break
            }
        }
        guard let frequency else { return nil }
        return RecurrenceRule(frequency: frequency, interval: interval, byDay: byDay, byMonthDay: byMonthDay, count: count, until: until)
    }
}
