import Foundation
import Observation

/// Where a position comes from. The app's implementation asks CoreLocation (reduced accuracy)
/// and only when the model calls it, which happens only while Weather is switched on.
public enum LocationResult: Equatable, Sendable {
    case coordinate(latitude: Double, longitude: Double)
    /// The owner refused (or restricted) location access.
    case denied
    /// No position this time (error, timeout, services off); silent.
    case unavailable
}

public protocol LocationSource: Sendable {
    func currentLocation() async -> LocationResult
}

public protocol WeatherTransport: Sendable {
    func fetch(_ url: URL) async throws -> Data
}

public struct WeatherHTTPError: Error, Equatable, Sendable {
    public let status: Int
}

/// The one network call Stark makes (opt-in). Sends only the request `WeatherRequest.url` builds.
public struct URLSessionWeatherTransport: WeatherTransport {
    public init() {}

    public static func request(for url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 15)
        r.httpMethod = "GET"
        r.setValue(WeatherRequest.userAgent, forHTTPHeaderField: "User-Agent")
        return r
    }

    public func fetch(_ url: URL) async throws -> Data {
        // An ephemeral session keeps no cookies or cache on disk.
        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(for: Self.request(for: url))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherHTTPError(status: http.statusCode)
        }
        return data
    }
}

/// Opt-in forecast for the agenda's day headers. OFF by default: while off nothing asks for the
/// location and nothing touches the network. Positions are never stored or logged; only the
/// rounded coordinate of the last fetch is kept in memory to decide when to refetch.
@MainActor @Observable
public final class WeatherModel {
    public static let defaultsKey = "weatherEnabled"
    public static let deniedMessage =
        "Weather needs your location. Allow it in iOS Settings > Privacy > Location Services > Stark, or turn Weather off."

    public private(set) var isEnabled: Bool
    /// Forecast by start of the local day.
    public private(set) var forecast: [Date: DayWeather] = [:]
    /// A one-line reason shown in the Settings footer (only for denied location).
    public private(set) var statusMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let transport: WeatherTransport
    @ObservationIgnored private let location: LocationSource
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var lastFetch: Date?
    @ObservationIgnored private var lastCoordinate: WeatherCoordinate?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isRefreshing = false

    public init(defaults: UserDefaults = .standard, transport: WeatherTransport = URLSessionWeatherTransport(),
                location: LocationSource, calendar: Calendar, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.transport = transport
        self.location = location
        self.calendar = calendar
        self.now = now
        self.isEnabled = defaults.bool(forKey: Self.defaultsKey)
    }

    /// The toggle. Turning it on asks for the location (the system prompt) and fetches.
    public func setEnabled(_ on: Bool) async {
        guard on != isEnabled else { return }
        isEnabled = on
        defaults.set(on, forKey: Self.defaultsKey)
        generation += 1
        if on {
            await refreshIfNeeded()
        } else {
            forecast = [:]
            statusMessage = nil
            lastFetch = nil
            lastCoordinate = nil
        }
    }

    /// Refetches when the forecast is over an hour old or the place moved by 0.1 degree. A fresh
    /// cache returns before the location or the network is touched.
    public func refreshIfNeeded() async {
        guard isEnabled, !isRefreshing else { return }
        if statusMessage == nil, let lastFetch {
            let age = now().timeIntervalSince(lastFetch)
            if age >= 0, age < WeatherRefreshPolicy.maxAge { return }
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let mine = generation

        let result = await location.currentLocation()
        guard mine == generation, isEnabled else { return }
        switch result {
        case .denied:
            statusMessage = Self.deniedMessage
            forecast = [:]
        case .unavailable:
            break
        case .coordinate(let lat, let lon):
            statusMessage = nil
            let coordinate = WeatherCoordinate.rounded(latitude: lat, longitude: lon)
            guard WeatherRefreshPolicy.needsFetch(enabled: isEnabled, lastFetch: lastFetch,
                                                  lastCoordinate: lastCoordinate, now: now(),
                                                  coordinate: coordinate) else { return }
            let moved = lastCoordinate != nil && lastCoordinate != coordinate
            do {
                let data = try await transport.fetch(WeatherRequest.url(latitude: coordinate.latitude,
                                                                        longitude: coordinate.longitude))
                let days = try METNorwayForecast.parse(data, calendar: calendar)
                guard mine == generation, isEnabled else { return }
                forecast = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
                lastFetch = now()
                lastCoordinate = coordinate
            } catch {
                guard mine == generation, isEnabled else { return }
                // Silent. An old forecast for another place would be wrong, so drop it then.
                if moved {
                    forecast = [:]
                    lastCoordinate = nil
                    lastFetch = nil
                }
            }
        }
    }
}
