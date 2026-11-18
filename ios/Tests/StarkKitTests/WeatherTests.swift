import Foundation
import Testing
@testable import StarkKit

private func calendar(_ zone: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zone)!
    return c
}

private let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private struct Hour {
    var time: String
    var temp: Double?
    var symbol: String?
}

/// A MET Norway `compact` response with the given hourly entries.
private func fixture(_ hours: [Hour]) -> Data {
    let entries = hours.map { h -> String in
        var instant = "\"instant\":{\"details\":{"
        if let t = h.temp { instant += "\"air_temperature\":\(t)" }
        instant += "}}"
        var next = ""
        if let s = h.symbol {
            next = ",\"next_1_hours\":{\"summary\":{\"symbol_code\":\"\(s)\"}}"
        }
        return "{\"time\":\"\(h.time)\",\"data\":{\(instant)\(next)}}"
    }
    return Data("{\"properties\":{\"timeseries\":[\(entries.joined(separator: ","))]}}".utf8)
}

/// `count` hourly entries from a UTC start; temperature and symbol per index.
private func run(start: String, count: Int, temp: (Int) -> Double? = { Double($0) },
                 symbol: (Int) -> String? = { _ in "cloudy" }) -> Data {
    let s = iso.date(from: start)!
    let hours = (0..<count).map { i -> Hour in
        let d = s.addingTimeInterval(Double(i) * 3600)
        return Hour(time: iso.string(from: d), temp: temp(i), symbol: symbol(i))
    }
    return fixture(hours)
}

@Suite("Weather forecast parsing")
struct WeatherParseTests {
    @Test func fixtureFromTheSpecShapeParses() throws {
        let json = """
        {"properties":{"timeseries":[
        {"time":"2026-11-18T09:00:00Z","data":{"instant":{"details":{"air_temperature":7.3}},"next_1_hours":{"summary":{"symbol_code":"partlycloudy_day"}}}},
        {"time":"2026-11-18T10:00:00Z","data":{"instant":{"details":{"air_temperature":9.1}},"next_1_hours":{"summary":{"symbol_code":"partlycloudy_day"}}}},
        {"time":"2026-11-18T11:00:00Z","data":{"instant":{"details":{"air_temperature":-2.0}},"next_1_hours":{"summary":{"symbol_code":"rain"}}}},
        {"time":"2026-11-18T12:00:00Z","data":{"instant":{"details":{"air_temperature":4.0}}}}
        ]}}
        """
        let days = try METNorwayForecast.parse(Data(json.utf8), calendar: calendar("UTC"))
        #expect(days.count == 1)
        #expect(days[0].high == 9.1)
        #expect(days[0].low == -2.0)
        #expect(days[0].symbol == .partlyCloudy)
    }

    @Test func highLowAndDayStartInUTC() throws {
        let cal = calendar("UTC")
        let data = run(start: "2026-11-18T00:00:00Z", count: 24)
        let days = try METNorwayForecast.parse(data, calendar: cal)
        #expect(days.count == 1)
        #expect(days[0].day == cal.startOfDay(for: iso.date(from: "2026-11-18T00:00:00Z")!))
        #expect(days[0].high == 23)
        #expect(days[0].low == 0)
    }

    @Test func tokyoGroupsByLocalDay() throws {
        let cal = calendar("Asia/Tokyo")
        // 10Z..14Z on the 18th = 19:00..23:00 JST (5 hours), then all of the 19th JST.
        let data = run(start: "2026-11-18T10:00:00Z", count: 29)
        let days = try METNorwayForecast.parse(data, calendar: cal)
        #expect(days.count == 2)
        #expect(days[0].day == cal.date(from: DateComponents(year: 2026, month: 11, day: 18))!)
        #expect(days[0].low == 0)
        #expect(days[0].high == 4)
        #expect(days[1].day == cal.date(from: DateComponents(year: 2026, month: 11, day: 19))!)
        #expect(days[1].low == 5)
        #expect(days[1].high == 28)
    }

    @Test func tokyoUTCEveningBelongsToNextLocalDay() throws {
        let cal = calendar("Asia/Tokyo")
        // 15Z on the 18th is midnight of the 19th in Tokyo: only 19th entries.
        let data = run(start: "2026-11-18T15:00:00Z", count: 24)
        let days = try METNorwayForecast.parse(data, calendar: cal)
        #expect(days.count == 1)
        #expect(days[0].day == cal.date(from: DateComponents(year: 2026, month: 11, day: 19))!)
    }

    @Test func honoluluUTCEveningBelongsToPreviousLocalDay() throws {
        let cal = calendar("Pacific/Honolulu")
        // 10Z on the 18th = 00:00 HST the 18th; 09Z on the 19th = 23:00 HST the 18th.
        let data = run(start: "2026-11-18T10:00:00Z", count: 24)
        let days = try METNorwayForecast.parse(data, calendar: cal)
        #expect(days.count == 1)
        #expect(days[0].day == cal.date(from: DateComponents(year: 2026, month: 11, day: 18))!)
        #expect(days[0].high == 23)
    }

    @Test func newYorkFallBackDayHasTwentyFiveHours() throws {
        let cal = calendar("America/New_York")
        // 2026-11-01 is 25 hours long in New York: 04Z (00:00 EDT) .. 04Z next day (23:00 EST).
        let data = run(start: "2026-11-01T04:00:00Z", count: 25)
        let days = try METNorwayForecast.parse(data, calendar: cal)
        #expect(days.count == 1)
        #expect(days[0].day == cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!)
        #expect(days[0].high == 24)
        #expect(days[0].low == 0)
    }

    @Test func newYorkSpringForwardDayHasTwentyThreeHours() throws {
        let cal = calendar("America/New_York")
        // 2026-03-08: 05Z (00:00 EST) .. 03Z next day (23:00 EDT) = 23 entries.
        let data = run(start: "2026-03-08T05:00:00Z", count: 23)
        let days = try METNorwayForecast.parse(data, calendar: cal)
        #expect(days.count == 1)
        #expect(days[0].high == 22)
    }

    @Test func onlyTheLastDayNeedsFourHours() throws {
        let cal = calendar("UTC")
        // The full 18th, then only 3 hours of the 19th (the last day): skipped.
        let data = run(start: "2026-11-18T00:00:00Z", count: 27)
        let days = try METNorwayForecast.parse(data, calendar: cal)
        #expect(days.count == 1)
        #expect(days[0].day == cal.startOfDay(for: iso.date(from: "2026-11-18T00:00:00Z")!))
        // Exactly four hours is kept.
        let four = try METNorwayForecast.parse(run(start: "2026-11-18T00:00:00Z", count: 28), calendar: cal)
        #expect(four.count == 2)
    }

    @Test func todayIsKeptEvenWithOneHourLeft() throws {
        let cal = calendar("UTC")
        // 23:00 on the 18th is today's only entry; the 19th is complete.
        let data = run(start: "2026-11-18T23:00:00Z", count: 25)
        let days = try METNorwayForecast.parse(data, calendar: cal)
        #expect(days.count == 2)
        #expect(days[0].day == cal.startOfDay(for: iso.date(from: "2026-11-18T23:00:00Z")!))
    }

    @Test func aMiddleDayWithFewHoursIsKept() throws {
        let cal = calendar("UTC")
        var hours: [Hour] = []
        for h in 0..<24 { hours.append(Hour(time: "2026-11-18T\(String(format: "%02d", h)):00:00Z", temp: 5, symbol: "cloudy")) }
        for h in [6, 18] { hours.append(Hour(time: "2026-11-19T\(String(format: "%02d", h)):00:00Z", temp: 6, symbol: "cloudy")) }
        for h in 0..<24 { hours.append(Hour(time: "2026-11-20T\(String(format: "%02d", h)):00:00Z", temp: 7, symbol: "cloudy")) }
        let days = try METNorwayForecast.parse(fixture(hours), calendar: cal)
        #expect(days.count == 3)
    }

    @Test func symbolIsTheMostFrequentDaytimeOne() throws {
        // Night hours rain; 08..19 mostly clear, a few cloudy.
        let data = run(start: "2026-11-18T00:00:00Z", count: 24, symbol: { i in
            if i < 8 || i >= 20 { return "rain" }
            return i % 4 == 0 ? "cloudy" : "clearsky_day"
        })
        let days = try METNorwayForecast.parse(data, calendar: calendar("UTC"))
        #expect(days[0].symbol == .clear)
    }

    @Test func symbolUsesLocalDaytimeNotUTC() throws {
        // Start 15Z = 00:00 JST, so index i is the JST hour. Snow in JST daytime, rain at night.
        let data = run(start: "2026-11-18T15:00:00Z", count: 24, symbol: { i in
            (8..<20).contains(i) ? "snow" : "rain"
        })
        let days = try METNorwayForecast.parse(data, calendar: calendar("Asia/Tokyo"))
        #expect(days[0].symbol == .snow)
    }

    @Test func symbolFallsBackToAllEntriesWhenNoDaytimeOnes() throws {
        let data = run(start: "2026-11-18T00:00:00Z", count: 24, symbol: { i in
            i < 6 ? "fog" : nil
        })
        let days = try METNorwayForecast.parse(data, calendar: calendar("UTC"))
        #expect(days[0].symbol == .fog)
    }

    @Test func noSymbolsAtAllGivesNoSymbolNotCloudy() throws {
        let data = run(start: "2026-11-18T00:00:00Z", count: 24, symbol: { _ in nil })
        let days = try METNorwayForecast.parse(data, calendar: calendar("UTC"))
        #expect(days.count == 1)
        #expect(days[0].symbol == nil)
        #expect(days[0].high == 23)
    }

    @Test func hoursWithoutNext1HoursStillCountForTemperature() throws {
        let data = run(start: "2026-11-18T00:00:00Z", count: 24, temp: { $0 == 3 ? 40 : 10 },
                       symbol: { $0 == 3 ? nil : "cloudy" })
        let days = try METNorwayForecast.parse(data, calendar: calendar("UTC"))
        #expect(days[0].high == 40)
    }

    @Test func entriesWithoutATemperatureAreIgnored() throws {
        let data = run(start: "2026-11-18T00:00:00Z", count: 24, temp: { $0 == 5 ? nil : Double($0) })
        let days = try METNorwayForecast.parse(data, calendar: calendar("UTC"))
        #expect(days[0].high == 23)
        #expect(days[0].low == 0)
    }

    @Test func unsortedInputStillGivesSortedDays() throws {
        func entries(_ d: Data) -> String {
            let s = String(decoding: d, as: UTF8.self)
            let start = s.range(of: "[")!.upperBound
            let end = s.range(of: "]}}", options: .backwards)!.lowerBound
            return String(s[start..<end])
        }
        let a = run(start: "2026-11-19T00:00:00Z", count: 24)
        let b = run(start: "2026-11-18T00:00:00Z", count: 24)
        let merged = Data("{\"properties\":{\"timeseries\":[\(entries(a)),\(entries(b))]}}".utf8)
        let days = try METNorwayForecast.parse(merged, calendar: calendar("UTC"))
        #expect(days.count == 2)
        #expect(days[0].day < days[1].day)
    }

    @Test func emptyTimeseriesIsAnEmptyForecast() throws {
        let data = Data("{\"properties\":{\"timeseries\":[]}}".utf8)
        #expect(try METNorwayForecast.parse(data, calendar: calendar("UTC")).isEmpty)
    }

    @Test func badJSONThrows() {
        for bad in ["not json", "{}", ""] {
            #expect(throws: (any Error).self) {
                _ = try METNorwayForecast.parse(Data(bad.utf8), calendar: calendar("UTC"))
            }
        }
    }

    @Test func badTimestampThrows() {
        let data = fixture([Hour(time: "yesterday", temp: 1, symbol: "rain")])
        #expect(throws: (any Error).self) {
            _ = try METNorwayForecast.parse(data, calendar: calendar("UTC"))
        }
    }
}

@Suite("Weather symbols")
struct WeatherSymbolTests {
    @Test func mapsMETCodes() {
        #expect(WeatherSymbol(metCode: "clearsky_day") == .clear)
        #expect(WeatherSymbol(metCode: "clearsky_night") == .clear)
        #expect(WeatherSymbol(metCode: "fair_polartwilight") == .clear)
        #expect(WeatherSymbol(metCode: "partlycloudy_day") == .partlyCloudy)
        #expect(WeatherSymbol(metCode: "partlycloudy_night") == .partlyCloudy)
        #expect(WeatherSymbol(metCode: "cloudy") == .cloudy)
        #expect(WeatherSymbol(metCode: "fog") == .fog)
        #expect(WeatherSymbol(metCode: "rain") == .rain)
        #expect(WeatherSymbol(metCode: "lightrainshowers_day") == .rain)
        #expect(WeatherSymbol(metCode: "heavyrain") == .rain)
        #expect(WeatherSymbol(metCode: "snow") == .snow)
        #expect(WeatherSymbol(metCode: "heavysnowshowers_night") == .snow)
        #expect(WeatherSymbol(metCode: "sleet") == .sleet)
        #expect(WeatherSymbol(metCode: "heavysleet") == .sleet)
        #expect(WeatherSymbol(metCode: "lightsleetshowers_day") == .sleet)
        #expect(WeatherSymbol(metCode: "lightrainandthunder") == .thunder)
        #expect(WeatherSymbol(metCode: "heavysnowandthunder") == .thunder)
        #expect(WeatherSymbol(metCode: "rainandthunder") == .thunder)
    }

    @Test func unknownCodeFallsBackToCloudy() {
        #expect(WeatherSymbol(metCode: "volcanicash") == .cloudy)
        #expect(WeatherSymbol(metCode: "") == .cloudy)
    }

    @Test func everySymbolHasNamesAndImages() {
        let all: [WeatherSymbol] = [.clear, .partlyCloudy, .cloudy, .fog, .rain, .snow, .sleet, .thunder]
        for s in all {
            #expect(!s.systemImageName.isEmpty)
            #expect(!s.spokenName.isEmpty)
        }
        #expect(Set(all.map(\.spokenName)).count == all.count)
        #expect(WeatherSymbol.rain.spokenName == "Rain")
    }
}

@Suite("Weather support")
struct WeatherSupportTests {
    private let here = WeatherCoordinate.rounded(latitude: 37.77, longitude: -122.42)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func coordinateRoundsToATenthOfADegree() {
        let c = WeatherCoordinate.rounded(latitude: 37.7749, longitude: -122.4194)
        #expect(c.latitude == 37.8)
        #expect(c.longitude == -122.4)
        let d = WeatherCoordinate.rounded(latitude: 51.4499, longitude: 0.06)
        #expect(d.latitude == 51.4)
        #expect(d.longitude == 0.1)
    }

    @Test func urlIsExactAndRounded() {
        let url = WeatherRequest.url(latitude: 37.7749, longitude: -122.4194)
        #expect(url.absoluteString ==
                "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=37.8&lon=-122.4")
        let z = WeatherRequest.url(latitude: -0.04, longitude: 0.0)
        #expect(z.absoluteString ==
                "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=0.0&lon=0.0")
        let de = WeatherRequest.url(latitude: 52.52, longitude: 13.405)
        #expect(de.absoluteString.contains("lat=52.5&lon=13.4"))
    }

    @Test func userAgentIsFixed() {
        #expect(WeatherRequest.userAgent == "Stark-iOS https://stark.caritos.com")
    }

    @Test func celsiusOutsideTheUS() {
        #expect(WeatherFormat.temperature(12, locale: Locale(identifier: "en_GB")) == "12°")
        #expect(WeatherFormat.temperature(12.4, locale: Locale(identifier: "de_DE")) == "12°")
        #expect(WeatherFormat.temperature(12.6, locale: Locale(identifier: "de_DE")) == "13°")
    }

    @Test func fahrenheitForTheUS() {
        let us = Locale(identifier: "en_US")
        #expect(WeatherFormat.temperature(12, locale: us) == "54°")
        #expect(WeatherFormat.temperature(0, locale: us) == "32°")
        #expect(WeatherFormat.temperature(-10, locale: us) == "14°")
    }

    @Test func theIOSTemperatureSettingWinsOverTheRegion() {
        // iOS carries the Settings > Language & Region > Temperature choice in the locale.
        #expect(WeatherFormat.temperature(12, locale: Locale(identifier: "en_US@mu=celsius")) == "12°")
        #expect(WeatherFormat.temperature(12, locale: Locale(identifier: "de_DE")) == "12°")
        #expect(WeatherFormat.temperature(12, locale: Locale(identifier: "en_US")) == "54°")
    }

    @Test func spokenWithoutASymbolStartsWithTheNumbers() {
        let d = DayWeather(day: Date(timeIntervalSince1970: 0), high: 12.2, low: 5.6, symbol: nil)
        #expect(WeatherFormat.spoken(d, locale: Locale(identifier: "en_GB")) == "High 12, low 6")
    }

    @Test func negativeZeroNeverShows() {
        let c = Locale(identifier: "en_GB")
        #expect(WeatherFormat.temperature(-0.4, locale: c) == "0°")
        #expect(WeatherFormat.temperature(-0.0, locale: c) == "0°")
        #expect(WeatherFormat.temperature(-0.6, locale: c) == "-1°")
        #expect(WeatherFormat.temperature(-5, locale: c) == "-5°")
        // -17.9 C = -0.22 F rounds to 0.
        #expect(WeatherFormat.temperature(-17.9, locale: Locale(identifier: "en_US")) == "0°")
    }

    @Test func spokenReadsWordAndNumbers() {
        let d = DayWeather(day: Date(timeIntervalSince1970: 0), high: 12.2, low: 5.6, symbol: .rain)
        #expect(WeatherFormat.spoken(d, locale: Locale(identifier: "en_GB")) == "Rain, high 12, low 6")
        #expect(WeatherFormat.spoken(d, locale: Locale(identifier: "en_US")) == "Rain, high 54, low 42")
    }

    @Test func disabledNeverFetches() {
        #expect(!WeatherRefreshPolicy.needsFetch(enabled: false, lastFetch: nil, lastCoordinate: nil,
                                                 now: now, coordinate: here))
        #expect(!WeatherRefreshPolicy.needsFetch(enabled: false, lastFetch: now.addingTimeInterval(-9999),
                                                 lastCoordinate: nil, now: now, coordinate: here))
    }

    @Test func firstFetchIsNeeded() {
        #expect(WeatherRefreshPolicy.needsFetch(enabled: true, lastFetch: nil, lastCoordinate: nil,
                                                now: now, coordinate: here))
        #expect(WeatherRefreshPolicy.needsFetch(enabled: true, lastFetch: now, lastCoordinate: nil,
                                                now: now, coordinate: here))
        #expect(WeatherRefreshPolicy.needsFetch(enabled: true, lastFetch: nil, lastCoordinate: here,
                                                now: now, coordinate: here))
    }

    @Test func staleAfterAnHour() {
        #expect(!WeatherRefreshPolicy.needsFetch(enabled: true, lastFetch: now.addingTimeInterval(-3599),
                                                 lastCoordinate: here, now: now, coordinate: here))
        #expect(WeatherRefreshPolicy.needsFetch(enabled: true, lastFetch: now.addingTimeInterval(-3600),
                                                lastCoordinate: here, now: now, coordinate: here))
    }

    @Test func movedLocationRefetches() {
        let moved = WeatherCoordinate.rounded(latitude: 37.9, longitude: -122.42)
        #expect(WeatherRefreshPolicy.needsFetch(enabled: true, lastFetch: now, lastCoordinate: here,
                                                now: now, coordinate: moved))
        let same = WeatherCoordinate.rounded(latitude: 37.76, longitude: -122.39)
        #expect(same == here)
        #expect(!WeatherRefreshPolicy.needsFetch(enabled: true, lastFetch: now, lastCoordinate: here,
                                                 now: now, coordinate: same))
    }

    @Test func aClockSetBackIsTreatedAsStale() {
        #expect(WeatherRefreshPolicy.needsFetch(enabled: true, lastFetch: now.addingTimeInterval(7200),
                                                lastCoordinate: here, now: now, coordinate: here))
    }
}


/// Shaped like the real MET `compact` feed: hourly entries (with `next_1_hours`) for about 60 hours,
/// then 6-hourly ones that carry only `next_6_hours` / `next_12_hours`; it starts partway through today.
private func realisticFeed() -> Data {
    let start = iso.date(from: "2026-11-18T14:00:00Z")!
    var entries: [String] = []
    func entry(_ date: Date, _ temp: Double, next: String) -> String {
        "{\"time\":\"\(iso.string(from: date))\",\"data\":{\"instant\":{\"details\":{\"air_temperature\":\(temp)}}\(next)}}"
    }
    for i in 0..<60 {
        let d = start.addingTimeInterval(Double(i) * 3600)
        entries.append(entry(d, 10 + Double(i % 5),
                             next: ",\"next_1_hours\":{\"summary\":{\"symbol_code\":\"cloudy\"}},\"next_6_hours\":{\"summary\":{\"symbol_code\":\"cloudy\"}}"))
    }
    var d = start.addingTimeInterval(60 * 3600)
    while d <= iso.date(from: "2026-11-27T00:00:00Z")! {
        entries.append(entry(d, 3,
                             next: ",\"next_6_hours\":{\"summary\":{\"symbol_code\":\"lightrain\"}},\"next_12_hours\":{\"summary\":{\"symbol_code\":\"snow\"}}"))
        d = d.addingTimeInterval(6 * 3600)
    }
    return Data("{\"properties\":{\"timeseries\":[\(entries.joined(separator: ","))]}}".utf8)
}

@Suite("Weather real feed shape")
struct WeatherRealFeedTests {
    @Test func sixHourlyDaysGetASymbolFromNext6Hours() throws {
        let cal = calendar("UTC")
        let days = try METNorwayForecast.parse(realisticFeed(), calendar: cal)
        let day24 = days.first { $0.day == cal.startOfDay(for: iso.date(from: "2026-11-24T00:00:00Z")!) }
        #expect(day24 != nil)
        #expect(day24?.symbol == .rain)
        #expect(day24?.high == 3)
    }

    @Test func todayStartedPartwayStillHasAForecast() throws {
        let cal = calendar("UTC")
        let days = try METNorwayForecast.parse(realisticFeed(), calendar: cal)
        #expect(days.first?.day == cal.startOfDay(for: iso.date(from: "2026-11-18T14:00:00Z")!))
        #expect(days.first?.symbol == .cloudy)
        // 18th to 26th; the 27th at 00:00Z alone is the skipped last day.
        #expect(days.count == 9)
    }

    @Test func next12HoursIsTheFallbackWhenThereIsNoNext6Hours() throws {
        let json = """
        {"properties":{"timeseries":[
        {"time":"2026-11-18T06:00:00Z","data":{"instant":{"details":{"air_temperature":1}},"next_12_hours":{"summary":{"symbol_code":"snow"}}}},
        {"time":"2026-11-18T12:00:00Z","data":{"instant":{"details":{"air_temperature":2}},"next_12_hours":{"summary":{"symbol_code":"snow"}}}},
        {"time":"2026-11-18T18:00:00Z","data":{"instant":{"details":{"air_temperature":0}}}}
        ]}}
        """
        let days = try METNorwayForecast.parse(Data(json.utf8), calendar: calendar("UTC"))
        #expect(days.count == 1)
        #expect(days[0].symbol == .snow)
    }

    @Test func nightCodesMapToTheSameFamiliesAndOnlyCountWhenNoDayEntries() throws {
        let cal = calendar("UTC")
        let night = run(start: "2026-11-18T00:00:00Z", count: 6, symbol: { _ in "partlycloudy_night" })
        let days = try METNorwayForecast.parse(night, calendar: cal)
        #expect(days.first?.symbol == .partlyCloudy)
        let mixed = run(start: "2026-11-18T00:00:00Z", count: 24, symbol: { i in
            (8..<20).contains(i) ? (i == 10 ? "rain" : nil) : "clearsky_night" })
        let d2 = try METNorwayForecast.parse(mixed, calendar: cal)
        #expect(d2.first?.symbol == .rain)
    }
}
