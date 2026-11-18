//
//  LocationProvider.swift
//  Stark
//
//  One-shot, reduced-accuracy location for the optional weather forecast. It is only ever called
//  by `WeatherModel` while Weather is switched on, so the system permission prompt appears only
//  then. The position is handed straight back and never stored or logged here. Callers that
//  arrive while a request is running (for example Weather switched off and on again) all wait
//  for that one request, and a position that never arrives ends as `.unavailable`.
//

import CoreLocation
import Foundation
import StarkKit

@MainActor
final class LocationProvider: NSObject, LocationSource, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authWaiters: [CheckedContinuation<Void, Never>] = []
    private var locationWaiters: [CheckedContinuation<LocationResult, Never>] = []
    private var timeoutTask: Task<Void, Never>?
    /// How long a requested position may take once access is granted (the permission prompt itself
    /// waits for the person as long as it needs).
    private static let positionTimeout: UInt64 = 20_000_000_000

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func currentLocation() async -> LocationResult {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                authWaiters.append(c)
                // One system prompt, however many callers wait for it.
                if authWaiters.count == 1 { manager.requestWhenInUseAuthorization() }
            }
        }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return .denied
        case .authorizedAlways, .authorizedWhenInUse:
            break
        default:
            return .unavailable
        }
        return await withCheckedContinuation { (c: CheckedContinuation<LocationResult, Never>) in
            locationWaiters.append(c)
            guard locationWaiters.count == 1 else { return }
            manager.requestLocation()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.positionTimeout)
                guard !Task.isCancelled else { return }
                self?.finish(.unavailable)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard manager.authorizationStatus != .notDetermined else { return }
            let waiters = authWaiters
            authWaiters = []
            for c in waiters { c.resume() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let result: LocationResult
        if let last = locations.last {
            result = .coordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        } else {
            result = .unavailable
        }
        Task { @MainActor in finish(result) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in finish(denied ? .denied : .unavailable) }
    }

    private func finish(_ result: LocationResult) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let waiters = locationWaiters
        locationWaiters = []
        for c in waiters { c.resume(returning: result) }
    }
}
