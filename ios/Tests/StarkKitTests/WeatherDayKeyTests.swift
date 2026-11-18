import Foundation
import Testing
@testable import StarkKit

@Suite("Weather forecast lookup by day")
struct WeatherDayKeyTests {
    private func gregorian(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }

    private func forecast(on y: Int, _ m: Int, _ d: Int, tz: String) -> [Date: DayWeather] {
        let cal = gregorian(tz)
        let day = cal.startOfDay(for: cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!)
        return [day: DayWeather(day: day, high: 20, low: 10, symbol: nil)]
    }

    @Test(arguments: ["Pacific/Honolulu", "America/New_York", "Asia/Tokyo", "Pacific/Kiritimati"])
    func noonAndMidnightAndLateEveningFindTheDay(tz: String) {
        let f = forecast(on: 2026, 11, 20, tz: tz)
        let cal = gregorian(tz)
        let zone = TimeZone(identifier: tz)!
        for (h, mi) in [(0, 0), (12, 0), (23, 59)] {
            let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: h, minute: mi))!
            #expect(WeatherForecastLookup.day(d, in: f, timeZone: zone) != nil)
        }
        let next = cal.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 0))!
        #expect(WeatherForecastLookup.day(next, in: f, timeZone: zone) == nil)
    }

    @Test(arguments: [Calendar.Identifier.buddhist, .hebrew, .islamic, .japanese])
    func otherCalendarsLandOnTheSameDay(id: Calendar.Identifier) {
        let tz = "Asia/Tokyo"
        let zone = TimeZone(identifier: tz)!
        let f = forecast(on: 2026, 11, 20, tz: tz)
        var other = Calendar(identifier: id)
        other.timeZone = zone
        // The day the view's own calendar computes for the same instant.
        let instant = gregorian(tz).date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 15))!
        let startInOther = other.startOfDay(for: instant)
        #expect(WeatherForecastLookup.day(startInOther, in: f, timeZone: zone) != nil)
        let nextInOther = other.date(byAdding: .day, value: 1, to: startInOther)!
        #expect(WeatherForecastLookup.day(nextInOther, in: f, timeZone: zone) == nil)
        // A date rebuilt from the other calendar's own year/month/day components.
        let c = other.dateComponents([.year, .month, .day], from: instant)
        let rebuilt = other.date(from: c)!
        #expect(WeatherForecastLookup.day(rebuilt, in: f, timeZone: zone) != nil)
    }

    @Test func aDateInTheModelsZoneIsFound() {
        let f = forecast(on: 2026, 11, 20, tz: "America/New_York")
        let ny = gregorian("America/New_York")
        let noon = ny.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        #expect(WeatherForecastLookup.day(noon, in: f, timeZone: TimeZone(identifier: "America/New_York")!) != nil)
    }
}
