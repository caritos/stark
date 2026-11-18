import Foundation

/// A position rounded to 0.1 degree (about 11 km). This is all that ever leaves the phone.
public struct WeatherCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public static func rounded(latitude: Double, longitude: Double) -> WeatherCoordinate {
        WeatherCoordinate(latitude: tenth(latitude), longitude: tenth(longitude))
    }

    /// Rounds to a tenth and never returns -0.0.
    static func tenth(_ v: Double) -> Double {
        let r = (v * 10).rounded() / 10
        return r == 0 ? 0 : r
    }
}

public enum WeatherRequest {
    public static let userAgent = "Stark-iOS https://stark.caritos.com"

    /// The request URL for a position, rounded again here so a precise one cannot be sent by mistake.
    public static func url(latitude: Double, longitude: Double) -> URL {
        let c = WeatherCoordinate.rounded(latitude: latitude, longitude: longitude)
        // String(format:) with the POSIX locale keeps "." as the decimal separator.
        let lat = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), c.latitude)
        let lon = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), c.longitude)
        return URL(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=\(lat)&lon=\(lon)")!
    }
}

public enum WeatherFormat {
    /// Follows the iOS temperature choice (Settings > General > Language & Region > Temperature,
    /// which lives in the locale) and otherwise the region: a formatter with the natural scale
    /// converts 100 C to Fahrenheit exactly when this locale wants Fahrenheit.
    static func usesFahrenheit(_ locale: Locale) -> Bool {
        let hundred = Measurement(value: 100, unit: UnitTemperature.celsius)
        let natural = MeasurementFormatter()
        natural.locale = locale
        natural.unitOptions = .naturalScale
        natural.numberFormatter.maximumFractionDigits = 0
        let provided = MeasurementFormatter()
        provided.locale = locale
        provided.unitOptions = .providedUnit
        provided.numberFormatter.maximumFractionDigits = 0
        return natural.string(from: hundred) != provided.string(from: hundred)
    }

    private static func rounded(_ celsius: Double, locale: Locale) -> Int {
        let v = usesFahrenheit(locale) ? celsius * 9 / 5 + 32 : celsius
        return Int(v.rounded())  // Int has no negative zero
    }

    /// "12°" in Celsius, "54°" for the US.
    public static func temperature(_ celsius: Double, locale: Locale) -> String {
        "\(rounded(celsius, locale: locale))°"
    }

    /// "Rain, high 12, low 6"; "High 12, low 6" when the day has no symbol.
    public static func spoken(_ day: DayWeather, locale: Locale) -> String {
        let numbers = "high \(rounded(day.high, locale: locale)), low \(rounded(day.low, locale: locale))"
        guard let symbol = day.symbol else { return numbers.prefix(1).uppercased() + numbers.dropFirst() }
        return "\(symbol.spokenName), \(numbers)"
    }
}

public enum WeatherRefreshPolicy {
    public static let maxAge: TimeInterval = 3600

    public static func needsFetch(enabled: Bool, lastFetch: Date?, lastCoordinate: WeatherCoordinate?,
                                  now: Date, coordinate: WeatherCoordinate) -> Bool {
        guard enabled else { return false }
        guard let lastFetch, let lastCoordinate else { return true }
        if lastCoordinate != coordinate { return true }
        let age = now.timeIntervalSince(lastFetch)
        // A negative age means the clock moved back: treat the cache as stale.
        return age < 0 || age >= maxAge
    }
}

/// Finds a day's forecast from any date the views hold. `WeatherModel.forecast` is keyed by the
/// start of the day in a Gregorian calendar in the zone the model captured at launch (`keyZone`).
/// The phone's zone may have changed since (`viewZone`, the zone the views draw days in), so the
/// lookup reads the calendar day (year, month, day) the date has in `viewZone` and maps that
/// day onto the stored key. What is guaranteed: a day label the phone shows now finds the forecast
/// stored under the same calendar day, in any calendar system the view uses, because only the
/// Gregorian year, month and day of the date in `viewZone` are used. After a zone change the stored
/// forecast was still grouped by the launch zone's days until the next refresh.
public enum WeatherForecastLookup {
    public static func day(_ date: Date, in forecast: [Date: DayWeather], viewZone: TimeZone,
                           keyZone: TimeZone) -> DayWeather? {
        var view = Calendar(identifier: .gregorian)
        view.timeZone = viewZone
        let c = view.dateComponents([.year, .month, .day], from: date)
        var keyCal = Calendar(identifier: .gregorian)
        keyCal.timeZone = keyZone
        guard let noon = keyCal.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12)) else {
            return nil
        }
        return forecast[keyCal.startOfDay(for: noon)]
    }
}

extension WeatherFormat {
    /// A cell's own VoiceOver label with the day's forecast appended ("..., Weather forecast, Rain,
    /// high 12, low 6"). A button's label replaces its children's, so the forecast has to be here.
    public static func label(_ base: String, weather: DayWeather?, locale: Locale) -> String {
        guard let weather else { return base }
        return "\(base), Weather forecast, \(spoken(weather, locale: locale))"
    }
}
