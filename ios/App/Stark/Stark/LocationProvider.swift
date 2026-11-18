//
//  LocationProvider.swift
//  Stark
//
//  One-shot, reduced-accuracy location for the optional weather forecast. It is only ever called
//  by `WeatherModel` while Weather is switched on, so the system permission prompt appears only
//  then. The position is handed straight back and never stored or logged here.
//

import CoreLocation
import Foundation
import StarkKit

@MainActor
final class LocationProvider: NSObject, LocationSource, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<LocationResult, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func currentLocation() async -> LocationResult {
        // One request at a time; a second caller just gets nothing this time.
        guard locationContinuation == nil, authContinuation == nil else { return .unavailable }
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                authContinuation = c
                manager.requestWhenInUseAuthorization()
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
            locationContinuation = c
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard manager.authorizationStatus != .notDetermined else { return }
            let c = authContinuation
            authContinuation = nil
            c?.resume()
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
        let c = locationContinuation
        locationContinuation = nil
        c?.resume(returning: result)
    }
}
