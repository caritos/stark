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
    /// While true the call never returns (a prompt nobody answers).
    var hangs = false
    func currentLocation() async -> LocationResult {
        calls += 1
        if hangs {
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        }
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

private func entry(_ hour: Int, day: Int = 18, temp: Double? = nil) -> String {
    let h = String(format: "%02d", hour)
    return "{\"time\":\"2026-11-\(day)T\(h):00:00Z\",\"data\":{\"instant\":{\"details\":{\"air_temperature\":\(temp ?? Double(hour - 4))}},\"next_1_hours\":{\"summary\":{\"symbol_code\":\"rain\"}}}}"
}

private func feed(_ entries: [String]) -> Data {
    Data("{\"properties\":{\"timeseries\":[\(entries.joined(separator: ","))]}}".utf8)
}

/// Eight hourly entries on 2026-11-18: enough for one day.
private let sample = Data(
    "{\"properties\":{\"timeseries\":[\((9..<17).map { entry($0) }.joined(separator: ","))]}}".utf8)

private let t0: Date = {
    let f = ISO8601DateFormatter()
    return f.date(from: "2026-11-18T12:00:00Z")!
}()

@MainActor
private func make(transport: FakeTransport = FakeTransport(), location: FakeLocation = FakeLocation(),
                  clock: Clock = Clock(t0),
                  locationTimeout: TimeInterval = 90) -> (WeatherModel, FakeTransport, FakeLocation, UserDefaults) {
    let suite = UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    transport.response = .success(sample)
    let m = WeatherModel(defaults: defaults, transport: transport, location: location,
                         calendar: utc, now: { clock.now }, locationTimeout: locationTimeout)
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

    @Test func deniedMessageNamesTheSettingsApp() async {
        let transport = FakeTransport()
        let location = FakeLocation()
        location.result = .denied
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let phone = WeatherModel(defaults: defaults, transport: transport, location: location,
                                 calendar: utc, now: { t0 })
        await phone.setEnabled(true)
        #expect(phone.statusMessage?.contains("Settings > Privacy & Security > Location Services") == true)
        #expect(phone.statusMessage?.contains("iOS") == false)
        let mac = WeatherModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, transport: transport,
                               location: location, calendar: utc, now: { t0 }, settingsAppName: "System Settings")
        await mac.setEnabled(true)
        #expect(mac.statusMessage?.contains("System Settings > Privacy & Security > Location Services") == true)
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


extension WeatherModelTests {
    @Test func launchPathFetchesWhenAlreadyEnabled() async {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: WeatherModel.defaultsKey)
        let transport = FakeTransport()
        transport.response = .success(sample)
        let m = WeatherModel(defaults: defaults, transport: transport, location: FakeLocation(),
                             calendar: utc, now: { t0 })
        await m.refreshIfNeeded()
        #expect(transport.requests.count == 1)
        #expect(m.forecast.count == 1)
    }

    @Test func todayKeepsTheEarlierHighAndLowAcrossRefreshes() async {
        let clock = Clock(t0)
        let (m, transport, _, _) = make(clock: clock)
        await m.setEnabled(true)
        let key = utc.startOfDay(for: t0)
        #expect(m.forecast[key]?.low == 5)
        #expect(m.forecast[key]?.high == 12)
        // Later: only the evening is left in the feed, and it is milder.
        transport.response = .success(feed((14..<20).map { entry($0, temp: 8) }))
        clock.now = t0.addingTimeInterval(3 * 3600 + 1)
        await m.refreshIfNeeded()
        #expect(transport.requests.count == 2)
        #expect(m.forecast[key]?.low == 5)
        #expect(m.forecast[key]?.high == 12)
        // A colder evening lowers the low.
        transport.response = .success(feed((20..<24).map { entry($0, temp: 1) }))
        clock.now = t0.addingTimeInterval(7 * 3600)
        await m.refreshIfNeeded()
        #expect(m.forecast[key]?.low == 1)
        #expect(m.forecast[key]?.high == 12)
    }

    @Test func futureDaysAreReplacedNotMerged() async {
        let clock = Clock(t0)
        let (m, transport, _, _) = make(clock: clock)
        transport.response = .success(feed((0..<24).map { entry($0, day: 19, temp: 20) }))
        await m.setEnabled(true)
        let tomorrow = utc.startOfDay(for: t0.addingTimeInterval(86400))
        #expect(m.forecast[tomorrow]?.high == 20)
        transport.response = .success(feed((0..<24).map { entry($0, day: 19, temp: 10) }))
        clock.now = t0.addingTimeInterval(3601)
        await m.refreshIfNeeded()
        #expect(m.forecast[tomorrow]?.high == 10)
        #expect(m.forecast[tomorrow]?.low == 10)
    }

    @Test func aMovedPlaceDoesNotMergeTodaysExtremes() async {
        let clock = Clock(t0)
        let (m, transport, location, _) = make(clock: clock)
        await m.setEnabled(true)
        location.result = .coordinate(latitude: 10, longitude: 10)
        transport.response = .success(feed((14..<20).map { entry($0, temp: 30) }))
        clock.now = t0.addingTimeInterval(3601)
        await m.refreshIfNeeded()
        let key = utc.startOfDay(for: t0)
        #expect(m.forecast[key]?.low == 30)
        #expect(m.forecast[key]?.high == 30)
    }

    @Test func daysBeforeTodayAreDropped() async {
        let (m, transport, _, _) = make()
        transport.response = .success(feed((0..<24).map { entry($0, day: 17) } + (0..<24).map { entry($0, day: 18) }))
        await m.setEnabled(true)
        #expect(m.forecast.count == 1)
    }

    @Test func forecastKeysAreTheAgendasDayKeys() async {
        // The agenda looks days up by `Calendar(identifier: .gregorian).startOfDay`.
        let (m, _, _, _) = make()
        await m.setEnabled(true)
        let key = utc.startOfDay(for: t0)
        #expect(m.forecast.keys.first == key)
        #expect(m.forecast[key] != nil)
    }

    @Test func aLocationThatNeverAnswersTimesOutAndLaterRefreshesWork() async {
        let (m, transport, location, _) = make(locationTimeout: 0.05)
        location.hangs = true
        await m.setEnabled(true)
        #expect(transport.requests.isEmpty)
        #expect(m.statusMessage == nil)
        location.hangs = false
        await m.refreshIfNeeded()
        #expect(transport.requests.count == 1)
        #expect(m.forecast.count == 1)
    }

    @Test func offThenOnDuringAFetchStillEndsWithAForecast() async {
        let slow = FirstSlowTransport(then: sample)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let m = WeatherModel(defaults: defaults, transport: slow, location: FakeLocation(),
                             calendar: utc, now: { t0 })
        let first = Task { await m.setEnabled(true) }
        await slow.waitUntilStarted()
        await m.setEnabled(false)
        await m.setEnabled(true)
        #expect(m.forecast.count == 1)
        slow.finishFirst(sample)
        await first.value
        #expect(m.isEnabled)
        #expect(m.forecast.count == 1)
    }

    @Test func offThenOnDuringALocationWaitStillEndsWithAForecast() async {
        let location = FakeLocation()
        location.hangs = true
        let transport = FakeTransport()
        transport.response = .success(sample)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let m = WeatherModel(defaults: defaults, transport: transport, location: location,
                             calendar: utc, now: { t0 }, locationTimeout: 60)
        let first = Task { await m.setEnabled(true) }
        while location.calls == 0 { await Task.yield() }
        await m.setEnabled(false)
        location.hangs = false
        await m.setEnabled(true)
        #expect(m.forecast.count == 1)
        first.cancel()
    }

    @Test func twoRefreshesAtOnceMakeOneRequest() async {
        let slow = SlowTransport()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: WeatherModel.defaultsKey)
        let m = WeatherModel(defaults: defaults, transport: slow, location: FakeLocation(),
                             calendar: utc, now: { t0 })
        let a = Task { await m.refreshIfNeeded() }
        await slow.waitUntilStarted()
        await m.refreshIfNeeded()
        slow.finish(sample)
        await a.value
        #expect(slow.count == 1)
        #expect(m.forecast.count == 1)
    }
}

private final class FirstSlowTransport: WeatherTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var started: CheckedContinuation<Void, Never>?
    private var calls = 0
    private let then: Data
    init(then: Data) { self.then = then }
    func fetch(_ url: URL) async throws -> Data {
        lock.lock()
        calls += 1
        let isFirst = calls == 1
        lock.unlock()
        if !isFirst { return then }
        return try await withCheckedThrowingContinuation { c in
            lock.lock()
            continuation = c
            let s = started
            started = nil
            lock.unlock()
            s?.resume()
        }
    }
    func waitUntilStarted() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if continuation != nil {
                lock.unlock()
                c.resume()
            } else {
                started = c
                lock.unlock()
            }
        }
    }
    func finishFirst(_ data: Data) {
        lock.lock()
        let c = continuation
        lock.unlock()
        c?.resume(returning: data)
    }
}

private final class SlowTransport: WeatherTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var started: CheckedContinuation<Void, Never>?
    private var didStart = false
    private(set) var count = 0
    func fetch(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { c in
            lock.lock()
            count += 1
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

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data("ok".utf8)
    nonisolated(unsafe) static var lastRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        StubProtocol.lastRequest = request
        let r = HTTPURLResponse(url: request.url!, statusCode: StubProtocol.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubProtocol.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("WeatherTransport session", .serialized)
struct WeatherSessionTests {
    private func transport() -> URLSessionWeatherTransport {
        let config = URLSessionWeatherTransport.makeConfiguration()
        config.protocolClasses = [StubProtocol.self]
        return URLSessionWeatherTransport(session: URLSession(configuration: config))
    }

    @Test func configurationSendsOnlyTheFixedHeaders() {
        let c = URLSessionWeatherTransport.makeConfiguration()
        let h = c.httpAdditionalHeaders as? [String: String]
        #expect(h == ["User-Agent": WeatherRequest.userAgent, "Accept": "application/json", "Accept-Language": "en"])
        #expect(c.httpCookieStorage == nil)
        #expect(c.urlCache == nil)
        #expect(c.timeoutIntervalForRequest == 15)
    }

    @Test func aNon2xxStatusThrowsTheStatus() async {
        StubProtocol.status = 503
        do {
            _ = try await transport().fetch(WeatherRequest.url(latitude: 1, longitude: 2))
            Issue.record("expected an error")
        } catch let e as WeatherHTTPError {
            #expect(e.status == 503)
        } catch {
            Issue.record("wrong error \(error)")
        }
    }

    @Test func a200ReturnsTheBodyWithTheUserAgentSent() async throws {
        StubProtocol.status = 200
        StubProtocol.body = Data("hello".utf8)
        let data = try await transport().fetch(WeatherRequest.url(latitude: 1, longitude: 2))
        #expect(data == Data("hello".utf8))
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "User-Agent") == WeatherRequest.userAgent)
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

@Suite("WeatherModel forecast(on:)")
@MainActor
struct WeatherModelLookupTests {
    private let noon18: Date = ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z")!

    @Test func nilWhileDisabledFoundWhenEnabledNilAfterDisable() async {
        let (m, _, _, _) = make()
        #expect(m.forecast(on: noon18) == nil)
        await m.setEnabled(true)
        #expect(m.forecast(on: noon18) != nil)
        await m.setEnabled(false)
        #expect(m.forecast(on: noon18) == nil)
        #expect(m.forecast.isEmpty)
    }

    @Test func aDayWithoutForecastIsNil() async {
        let (m, _, _, _) = make()
        await m.setEnabled(true)
        #expect(m.forecast(on: noon18.addingTimeInterval(3 * 86_400)) == nil)
    }

    @Test func timeZoneChangedAfterLaunchStillFindsTheShownDay() async {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let transport = FakeTransport()
        transport.response = .success(sample)
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let zoneBox = ZoneBox(TimeZone(identifier: "Asia/Tokyo")!)
        let m = WeatherModel(defaults: defaults, transport: transport, location: FakeLocation(),
                             calendar: tokyo, now: { t0 }, viewTimeZone: { zoneBox.zone })
        await m.setEnabled(true)
        guard let shownDay = m.forecast.keys.first else { Issue.record("no forecast"); return }
        // The phone moves to Honolulu, where the same calendar day label has another instant.
        zoneBox.zone = TimeZone(identifier: "Pacific/Honolulu")!
        var honolulu = Calendar(identifier: .gregorian)
        honolulu.timeZone = zoneBox.zone
        let c = tokyo.dateComponents([.year, .month, .day], from: shownDay)
        let honoluluNoon = honolulu.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12))!
        #expect(m.forecast(on: honoluluNoon) != nil)
    }
}

private final class ZoneBox: @unchecked Sendable {
    var zone: TimeZone
    init(_ z: TimeZone) { zone = z }
}
