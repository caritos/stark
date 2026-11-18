import Foundation

/// One local day's forecast. Temperatures are Celsius.
public struct DayWeather: Equatable, Sendable {
    /// Start of the local day.
    public var day: Date
    public var high: Double
    public var low: Double
    public var symbol: WeatherSymbol

    public init(day: Date, high: Double, low: Double, symbol: WeatherSymbol) {
        self.day = day
        self.high = high
        self.low = low
        self.symbol = symbol
    }
}
