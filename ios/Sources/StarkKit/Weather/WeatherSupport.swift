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
    private static func usesFahrenheit(_ locale: Locale) -> Bool {
        locale.measurementSystem == .us
    }

    private static func rounded(_ celsius: Double, locale: Locale) -> Int {
        let v = usesFahrenheit(locale) ? celsius * 9 / 5 + 32 : celsius
        return Int(v.rounded())  // Int has no negative zero
    }

    /// "12°" in Celsius, "54°" for the US.
    public static func temperature(_ celsius: Double, locale: Locale) -> String {
        "\(rounded(celsius, locale: locale))°"
    }

    /// "Rain, high 12, low 6".
    public static func spoken(_ day: DayWeather, locale: Locale) -> String {
        "\(day.symbol.spokenName), high \(rounded(day.high, locale: locale)), low \(rounded(day.low, locale: locale))"
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
