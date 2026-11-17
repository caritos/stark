// ios/App/Stark/Stark/ErrorCenter.swift
import Foundation
import Observation

/// The main screen's error banner (accent bar, tap to dismiss): a failed Apple write, a failed
/// read of the sidecar's plans (`PlanCache.onLoadFailure`) or a checkbox completion that did not
/// reach EventKit. Shared through the environment; `ContentView` draws it and the full-screen
/// planner repeats it, since it covers the main screen. It stays until tapped or replaced.
@MainActor @Observable
final class ErrorCenter {
    private(set) var message: String?

    func show(_ message: String) {
        self.message = message
    }

    func dismiss() {
        message = nil
    }
}
