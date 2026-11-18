import Foundation
import Testing
@testable import StarkKit

private final class FakeTransport: WeatherTransport, @unchecked Sendable {
    var requests: [URL] = []
    var response: Result<Data, Error> = .success(Data())
    func fetch(_ url: URL) async throws -> Data {
        requests.append(url)
        return try response.get()
    }
}

private final class FakeLocation: LocationSource, @unchecked Sendable {
    var calls = 0
    var result: LocationResult = .coordinate(latitude: 37.7749, longitude: -122.4194)
    func currentLocation() async -> LocationResult {
        calls += 1
        return result
    }
}

private struct Boom: Error {}

private final class Clock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func entry(_ hour: Int) -> String {
    let h = String(format: "%02d", hour)
    return "{\"time\":\"2026-11-18T\(h):00:00Z\",\"data\":{\"instant\":{\"details\":{\"air_temperature\":\(hour - 4).0}},\"next_1_hours\":{\"summary\":{\"symbol_code\":\"rain\"}}}}"
}

/// Eight hourly entries on 2026-11-18: enough for one day.
private let sample = Data(
    "{\"properties\":{\"timeseries\":[\((9..<17).map(entry).joined(separator: ","))]}}".utf8)

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
private func make(transport: FakeTransport = FakeTransport(), location: FakeLocation = FakeLocation(),
                  clock: Clock = Clock(t0)) -> (WeatherModel, FakeTransport, FakeLocation, UserDefaults) {
    let suite = UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    transport.response = .success(sample)
    let m = WeatherModel(defaults: defaults, transport: transport, location: location,
                         calendar: utc, now: { clock.now })
    return (m, transport, location, defaults)
}

@Suite("WeatherModel")
@MainActor
struct WeatherModelTests {
    @Test func offByDefaultAndNeverTouchesLocationOrNetwork() async {
        let (m, transport, location, _) = make()
        #expect(m.isEnabled == false)
        await m.refreshIfNeeded()
        #expect(transport.requests.isEmpty)
        #expect(location.calls == 0)
        #expect(m.forecast.isEmpty)
    }

    @Test func enablingFetchesWithRoundedCoordinates() async {
        let (m, transport, location, defaults) = make()
        await m.setEnabled(true)
        #expect(defaults.bool(forKey: WeatherModel.defaultsKey))
        #expect(location.calls == 1)
        #expect(transport.requests.count == 1)
        let url = transport.requests[0].absoluteString
        #expect(url.contains("lat=37.8"))
        #expect(url.contains("lon=-122.4"))
        #expect(!url.contains("37.77"))
        #expect(m.forecast.count == 1)
        #expect(m.forecast.values.first?.symbol == .rain)
    }

    @Test func persistedEnabledStateIsReadBack() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: WeatherModel.defaultsKey)
        let m = WeatherModel(defaults: defaults, transport: FakeTransport(), location: FakeLocation(),
                             calendar: utc, now: { t0 })
        #expect(m.isEnabled)
    }

    @Test func freshCacheIsReusedWithoutLocationOrNetwork() async {
        let (m, transport, location, _) = make()
        await m.setEnabled(true)
        await m.refreshIfNeeded()
        #expect(transport.requests.count == 1)
        #expect(location.calls == 1)
    }

    @Test func staleAfterAnHourRefetches() async {
        let clock = Clock(t0)
        let (m, transport, _, _) = make(clock: clock)
        await m.setEnabled(true)
        clock.now = t0.addingTimeInterval(3601)
        await m.refreshIfNeeded()
        #expect(transport.requests.count == 2)
    }

    @Test func movedLocationRefetches() async {
        let clock = Clock(t0)
        let (m, transport, location, _) = make(clock: clock)
        await m.setEnabled(true)
        location.result = .coordinate(latitude: 40.7, longitude: -74.0)
        clock.now = t0.addingTimeInterval(3601)
        await m.refreshIfNeeded()
        #expect(transport.requests.count == 2)
        #expect(transport.requests[1].absoluteString.contains("lat=40.7"))
    }

    @Test func disablingClearsForecastAndStopsRequests() async {
        let (m, transport, location, defaults) = make()
        await m.setEnabled(true)
        await m.setEnabled(false)
        #expect(m.forecast.isEmpty)
        #expect(m.statusMessage == nil)
        #expect(defaults.bool(forKey: WeatherModel.defaultsKey) == false)
        await m.refreshIfNeeded()
        #expect(transport.requests.count == 1)
        #expect(location.calls == 1)
    }

    @Test func deniedLocationSetsStatusAndMakesNoRequest() async {
        let (m, transport, location, _) = make()
        location.result = .denied
        await m.setEnabled(true)
        #expect(transport.requests.isEmpty)
        #expect(m.statusMessage?.contains("location") == true)
        #expect(m.forecast.isEmpty)
    }

    @Test func statusClearsWhenLocationWorksAgain() async {
        let (m, _, location, _) = make()
        location.result = .denied
        await m.setEnabled(true)
        location.result = .coordinate(latitude: 1, longitude: 1)
        await m.refreshIfNeeded()
        #expect(m.statusMessage == nil)
        #expect(m.forecast.count == 1)
    }

    @Test func unavailableLocationIsSilent() async {
        let (m, transport, location, _) = make()
        location.result = .unavailable
        await m.setEnabled(true)
        #expect(transport.requests.isEmpty)
        #expect(m.statusMessage == nil)
    }

    @Test func httpErrorOrOfflineIsSilentAndLeavesNoForecast() async {
        let (m, transport, _, _) = make()
        transport.response = .failure(Boom())
        await m.setEnabled(true)
        #expect(m.forecast.isEmpty)
        #expect(m.statusMessage == nil)
    }

    @Test func badJSONIsSilent() async {
        let (m, transport, _, _) = make()
        transport.response = .success(Data("not json".utf8))
        await m.setEnabled(true)
        #expect(m.forecast.isEmpty)
        #expect(m.statusMessage == nil)
    }

    @Test func emptyTimeseriesGivesNoForecast() async {
        let (m, transport, _, _) = make()
        transport.response = .success(Data("{\"properties\":{\"timeseries\":[]}}".utf8))
        await m.setEnabled(true)
        #expect(m.forecast.isEmpty)
    }

    @Test func aFailedRefreshOnAMovedLocationDropsTheOldForecast() async {
        let clock = Clock(t0)
        let (m, transport, location, _) = make(clock: clock)
        await m.setEnabled(true)
        #expect(!m.forecast.isEmpty)
        location.result = .coordinate(latitude: 51.5, longitude: -0.1)
        transport.response = .failure(Boom())
        clock.now = t0.addingTimeInterval(3601)
        await m.refreshIfNeeded()
        #expect(m.forecast.isEmpty)
    }

    @Test func aFailedRefreshAtTheSamePlaceKeepsTheForecastAndRetriesNextTime() async {
        let clock = Clock(t0)
        let (m, transport, _, _) = make(clock: clock)
        await m.setEnabled(true)
        transport.response = .failure(Boom())
        clock.now = t0.addingTimeInterval(3601)
        await m.refreshIfNeeded()
        #expect(!m.forecast.isEmpty)
        transport.response = .success(sample)
        await m.refreshIfNeeded()
        #expect(transport.requests.count == 3)
    }

    @Test func turningOffDuringAFetchDiscardsTheResult() async {
        let slow = SlowTransport()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let m = WeatherModel(defaults: defaults, transport: slow, location: FakeLocation(),
                             calendar: utc, now: { t0 })
        let task = Task { await m.setEnabled(true) }
        await slow.waitUntilStarted()
        await m.setEnabled(false)
        slow.finish(sample)
        await task.value
        #expect(m.forecast.isEmpty)
        #expect(m.isEnabled == false)
    }
}

private final class SlowTransport: WeatherTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var started: CheckedContinuation<Void, Never>?
    private var didStart = false
    func fetch(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { c in
            lock.lock()
            continuation = c
            didStart = true
            let s = started
            started = nil
            lock.unlock()
            s?.resume()
        }
    }
    func waitUntilStarted() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if didStart {
                lock.unlock()
                c.resume()
            } else {
                started = c
                lock.unlock()
            }
        }
    }
    func finish(_ data: Data) {
        lock.lock()
        let c = continuation
        lock.unlock()
        c?.resume(returning: data)
    }
}

@Suite("WeatherTransport request")
struct WeatherRequestBuildTests {
    @Test func carriesUserAgentAndTimeout() {
        let url = WeatherRequest.url(latitude: 1, longitude: 2)
        let r = URLSessionWeatherTransport.request(for: url)
        #expect(r.value(forHTTPHeaderField: "User-Agent") == WeatherRequest.userAgent)
        #expect(r.timeoutInterval == 15)
        #expect(r.url == url)
        #expect(r.httpMethod == "GET")
    }
}
