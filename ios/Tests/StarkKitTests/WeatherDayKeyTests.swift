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

    private func zone(_ id: String) -> TimeZone { TimeZone(identifier: id)! }

    /// A forecast for 2026-11-20 keyed the way the model keys it (start of day in `tz`).
    private func forecast(tz: String) -> [Date: DayWeather] {
        let cal = gregorian(tz)
        let day = cal.startOfDay(for: cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!)
        return [day: DayWeather(day: day, high: 20, low: 10, symbol: nil)]
    }

    @Test(arguments: ["Pacific/Honolulu", "America/New_York", "Asia/Tokyo", "Pacific/Kiritimati"])
    func anyTimeOfTheDayFindsTheDayInTheSameZone(tz: String) {
        let f = forecast(tz: tz)
        let cal = gregorian(tz)
        for (h, mi) in [(0, 0), (12, 0), (23, 59)] {
            let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: h, minute: mi))!
            #expect(WeatherForecastLookup.day(d, in: f, viewZone: zone(tz), keyZone: zone(tz)) != nil)
        }
        let next = cal.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 0))!
        #expect(WeatherForecastLookup.day(next, in: f, viewZone: zone(tz), keyZone: zone(tz)) == nil)
    }

    /// Launch in Tokyo, move to Honolulu: Honolulu's Nov 20 noon is Nov 21 07:00 in Tokyo, so a
    /// lookup in the model's zone would land on the wrong day. The lookup goes by the day the
    /// phone shows now (the view's zone), then maps that calendar day onto the stored key.
    @Test func aZoneChangeAfterLaunchStillLandsOnTheDayShown() {
        let f = forecast(tz: "Asia/Tokyo")
        let honolulu = gregorian("Pacific/Honolulu")
        let noon = honolulu.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        #expect(WeatherForecastLookup.day(noon, in: f, viewZone: zone("Pacific/Honolulu"), keyZone: zone("Asia/Tokyo"))?.high == 20)
        // Honolulu's Nov 21 has no forecast, not Nov 20's.
        let nextNoon = honolulu.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 12))!
        #expect(WeatherForecastLookup.day(nextNoon, in: f, viewZone: zone("Pacific/Honolulu"), keyZone: zone("Asia/Tokyo")) == nil)
        // The old behaviour (model zone for both) is the day after.
        #expect(WeatherForecastLookup.day(noon, in: f, viewZone: zone("Asia/Tokyo"), keyZone: zone("Asia/Tokyo")) == nil)
    }

    @Test func eastToWestAndBackBothWork() {
        let f = forecast(tz: "Pacific/Honolulu")
        let tokyo = gregorian("Asia/Tokyo")
        let noon = tokyo.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        #expect(WeatherForecastLookup.day(noon, in: f, viewZone: zone("Asia/Tokyo"), keyZone: zone("Pacific/Honolulu")) != nil)
    }

    @Test func spokenLabelAppendsTheForecastAfterTheCellLabel() {
        let day = DayWeather(day: Date(), high: 12, low: 6, symbol: .rain)
        let locale = Locale(identifier: "en_GB")
        #expect(WeatherFormat.label("Friday, Nov 20", weather: day, locale: locale)
                == "Friday, Nov 20, Weather forecast, \(WeatherFormat.spoken(day, locale: locale))")
        #expect(WeatherFormat.label("Friday, Nov 20", weather: nil, locale: locale) == "Friday, Nov 20")
    }
}
