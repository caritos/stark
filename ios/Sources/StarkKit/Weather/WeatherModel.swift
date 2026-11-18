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
/// One ephemeral session (no cookies, no cache, nothing on disk) is reused for the app's lifetime.
public struct URLSessionWeatherTransport: WeatherTransport {
    private let session: URLSession

    public init() {
        self.session = URLSession(configuration: Self.makeConfiguration())
    }

    public init(session: URLSession) {
        self.session = session
    }

    /// The only headers ever sent beyond the standard ones: the identifying User-Agent, the JSON
    /// type, and a fixed language (the phone's language is not sent).
    public static func makeConfiguration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.httpAdditionalHeaders = ["User-Agent": WeatherRequest.userAgent,
                                   "Accept": "application/json",
                                   "Accept-Language": "en"]
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        return c
    }

    public static func request(for url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 15)
        r.httpMethod = "GET"
        r.setValue(WeatherRequest.userAgent, forHTTPHeaderField: "User-Agent")
        return r
    }

    public func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: Self.request(for: url))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherHTTPError(status: http.statusCode)
        }
        return data
    }
}

/// Resumes with the first of two results; a never-finishing operation cannot hold it back.
private final class FirstResult<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    private var done = false

    static func race(timeout: TimeInterval, _ operation: @escaping @Sendable () async -> T) async -> T? {
        let box = FirstResult<T>()
        return await withCheckedContinuation { (c: CheckedContinuation<T?, Never>) in
            box.continuation = c
            Task { box.finish(await operation()) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                box.finish(nil)
            }
        }
    }

    private func finish(_ value: T?) {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}

/// Opt-in forecast for the agenda's day headers. OFF by default: while off nothing asks for the
/// location and nothing touches the network. Positions are never stored or logged; only the
/// rounded coordinate of the last fetch is kept in memory to decide when to refetch.
@MainActor @Observable
public final class WeatherModel {
    public static let defaultsKey = "weatherEnabled"
    /// The one-line footer for a denied location; `settingsAppName` is "System Settings" on a Mac.
    public static func deniedMessage(settingsAppName: String) -> String {
        "Weather needs your location. Allow it in \(settingsAppName) > Privacy & Security > Location Services > Stark, or turn Weather off."
    }

    public private(set) var isEnabled: Bool
    /// Forecast by start of the local day.
    public private(set) var forecast: [Date: DayWeather] = [:]
    /// The forecast for the day containing `date`, or nil: nothing while Weather is off, and
    /// nothing for a day the feed does not cover. Normalises the date (see `WeatherForecastLookup`).
    public func forecast(on date: Date) -> DayWeather? {
        guard isEnabled else { return nil }
        return WeatherForecastLookup.day(date, in: forecast, timeZone: calendar.timeZone)
    }

    /// A one-line reason shown in the Settings footer (only for denied location).
    public private(set) var statusMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let transport: WeatherTransport
    @ObservationIgnored private let location: LocationSource
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var lastFetch: Date?
    @ObservationIgnored private var lastCoordinate: WeatherCoordinate?
    @ObservationIgnored private let locationTimeout: TimeInterval
    @ObservationIgnored private let settingsAppName: String
    @ObservationIgnored private var generation = 0
    /// The generation a refresh is running for. A second call for the same generation is a
    /// duplicate; one for a newer generation (off then on) starts its own and the old one is dropped.
    @ObservationIgnored private var inFlightGeneration: Int?

    public init(defaults: UserDefaults = .standard, transport: WeatherTransport = URLSessionWeatherTransport(),
                location: LocationSource, calendar: Calendar, now: @escaping @Sendable () -> Date = { Date() },
                locationTimeout: TimeInterval = 90, settingsAppName: String = "Settings") {
        self.locationTimeout = locationTimeout
        self.settingsAppName = settingsAppName
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
    /// cache returns before the location or the network is touched. Call it at launch and when
    /// the app becomes active; it does nothing while Weather is off.
    public func refreshIfNeeded() async {
        guard isEnabled else { return }
        let mine = generation
        guard inFlightGeneration != mine else { return }
        if statusMessage == nil, let lastFetch {
            let age = now().timeIntervalSince(lastFetch)
            if age >= 0, age < WeatherRefreshPolicy.maxAge { return }
        }
        inFlightGeneration = mine
        defer { if inFlightGeneration == mine { inFlightGeneration = nil } }

        // A prompt nobody answers, or a position that never arrives, must not hold the model.
        let source = location
        let result = await FirstResult.race(timeout: locationTimeout) { await source.currentLocation() }
        guard mine == generation, isEnabled else { return }
        switch result {
        case .none, .some(.unavailable):
            break
        case .some(.denied):
            statusMessage = Self.deniedMessage(settingsAppName: settingsAppName)
            forecast = [:]
        case .some(.coordinate(let lat, let lon)):
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
                forecast = merged(days, keepingTodaysExtremes: !moved)
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

    /// Past days are dropped. The feed only holds today's remaining hours, so today keeps the
    /// extremes of earlier fetches (in memory only, never persisted) while the place is unchanged.
    private func merged(_ days: [DayWeather], keepingTodaysExtremes: Bool) -> [Date: DayWeather] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = calendar.timeZone
        let today = cal.startOfDay(for: now())
        var result: [Date: DayWeather] = [:]
        for day in days where day.day >= today {
            var entry = day
            if keepingTodaysExtremes, day.day == today, let old = forecast[today] {
                entry.high = max(old.high, day.high)
                entry.low = min(old.low, day.low)
                entry.symbol = day.symbol ?? old.symbol
            }
            result[day.day] = entry
        }
        return result
    }
}
