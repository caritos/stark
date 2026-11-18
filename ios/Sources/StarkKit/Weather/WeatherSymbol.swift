import Foundation

public enum WeatherSymbol: String, Sendable {
    case clear, partlyCloudy, cloudy, fog, rain, snow, sleet, thunder

    /// Maps a MET Norway `symbol_code` such as `partlycloudy_day`; unknown codes read as cloudy.
    public init(metCode: String) {
        var code = metCode
        for suffix in ["_day", "_night", "_polartwilight"] where code.hasSuffix(suffix) {
            code = String(code.dropLast(suffix.count))
        }
        if code.contains("thunder") { self = .thunder }
        else if code.contains("sleet") { self = .sleet }
        else if code.contains("snow") { self = .snow }
        else if code.contains("rain") { self = .rain }
        else if code == "clearsky" || code == "fair" { self = .clear }
        else if code == "partlycloudy" { self = .partlyCloudy }
        else if code == "fog" { self = .fog }
        else { self = .cloudy }
    }

    public var systemImageName: String {
        switch self {
        case .clear: "sun.max.fill"
        case .partlyCloudy: "cloud.sun.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .sleet: "cloud.sleet.fill"
        case .thunder: "cloud.bolt.rain.fill"
        }
    }

    public var spokenName: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .cloudy: "Cloudy"
        case .fog: "Fog"
        case .rain: "Rain"
        case .snow: "Snow"
        case .sleet: "Sleet"
        case .thunder: "Thunderstorm"
        }
    }
}
