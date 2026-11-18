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
/// start of the day in a Gregorian calendar in the model's time zone; a view's own `Calendar`
/// (another calendar system, or a time zone captured earlier) may build a different `Date` for
/// the same day, so every lookup normalises through that Gregorian start of day first.
public enum WeatherForecastLookup {
    public static func key(for date: Date, timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.startOfDay(for: date)
    }

    public static func day(_ date: Date, in forecast: [Date: DayWeather], timeZone: TimeZone) -> DayWeather? {
        forecast[key(for: date, timeZone: timeZone)]
    }
}
