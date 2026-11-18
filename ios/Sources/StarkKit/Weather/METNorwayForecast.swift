import Foundation

/// Parses a MET Norway Locationforecast 2.0 `compact` response into per-local-day forecasts.
public enum METNorwayForecast {
    /// A day needs at least this many hourly entries; fewer would give a misleading high/low.
    static let minimumHours = 4

    private struct Response: Decodable {
        struct Properties: Decodable {
            struct Entry: Decodable {
                struct DataBlock: Decodable {
                    struct Instant: Decodable {
                        struct Details: Decodable { var air_temperature: Double? }
                        var details: Details?
                    }
                    struct Next: Decodable {
                        struct Summary: Decodable { var symbol_code: String? }
                        var summary: Summary?
                    }
                    var instant: Instant?
                    var next_1_hours: Next?
                    var next_6_hours: Next?
                    var next_12_hours: Next?
                }
                var time: String
                var data: DataBlock?
            }
            var timeseries: [Entry]
        }
        var properties: Properties
    }

    private struct Hour {
        var date: Date
        var temp: Double
        var symbol: WeatherSymbol?
    }

    public static func parse(_ data: Data, calendar: Calendar) throws -> [DayWeather] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        // Day math in Gregorian with the given calendar's time zone, whatever the phone calendar.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = calendar.timeZone

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var byDay: [Date: [Hour]] = [:]
        for entry in response.properties.timeseries {
            guard let date = parser.date(from: entry.time) ?? fractional.date(from: entry.time) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [],
                    debugDescription: "Bad timestamp \(entry.time)"))
            }
            guard let temp = entry.data?.instant?.details?.air_temperature else { continue }
            // The feed is hourly for about 60 hours, then 6-hourly: later entries carry only
            // `next_6_hours` (and `next_12_hours`), so take the shortest summary that exists.
            let code = entry.data?.next_1_hours?.summary?.symbol_code
                ?? entry.data?.next_6_hours?.summary?.symbol_code
                ?? entry.data?.next_12_hours?.summary?.symbol_code
            let symbol = code.map(WeatherSymbol.init(metCode:))
            byDay[cal.startOfDay(for: date), default: []].append(Hour(date: date, temp: temp, symbol: symbol))
        }

        let sortedDays = byDay.keys.sorted()
        let lastDay = sortedDays.last
        return sortedDays.compactMap { day -> DayWeather? in
            let hours = byDay[day]!
            // Only the feed's last day can be a stub that would give a misleading high/low. Today
            // (the first day) is partial too, and stays; a gap in the middle is kept.
            if day == lastDay, day != sortedDays.first, hours.count < minimumHours { return nil }
            if day == lastDay, day == sortedDays.first, hours.isEmpty { return nil }
            let daytime = hours.filter {
                let h = cal.component(.hour, from: $0.date)
                return h >= 8 && h < 20 && $0.symbol != nil
            }
            let pool = daytime.isEmpty ? hours.filter { $0.symbol != nil } : daytime
            return DayWeather(day: day,
                              high: hours.map(\.temp).max()!,
                              low: hours.map(\.temp).min()!,
                              symbol: mostFrequent(pool.compactMap(\.symbol)))
        }
    }

    /// Most frequent symbol; ties go to the earliest in the day. No symbols gives nil (never "cloudy").
    private static func mostFrequent(_ symbols: [WeatherSymbol]) -> WeatherSymbol? {
        var counts: [WeatherSymbol: Int] = [:]
        var order: [WeatherSymbol] = []
        for s in symbols {
            if counts[s] == nil { order.append(s) }
            counts[s, default: 0] += 1
        }
        return order.max { counts[$0]! < counts[$1]! }
    }
}
