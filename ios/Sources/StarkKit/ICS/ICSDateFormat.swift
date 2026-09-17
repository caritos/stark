import Foundation

public enum ICSDateFormat {
    private static func formatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = pattern
        return formatter
    }

    public static func format(_ date: Date, allDay: Bool) -> String {
        formatter(allDay ? "yyyyMMdd" : "yyyyMMdd'T'HHmmss").string(from: date)
    }

    public static func parse(_ value: String) -> (date: Date, allDay: Bool)? {
        let cleaned = value.replacingOccurrences(of: "Z", with: "")
        if cleaned.count == 8 {
            guard let date = formatter("yyyyMMdd").date(from: cleaned) else { return nil }
            return (date, true)
        }
        guard let date = formatter("yyyyMMdd'T'HHmmss").date(from: cleaned) else { return nil }
        return (date, false)
    }
}
