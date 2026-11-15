// ios/App/Stark/Stark/NoticeCenter.swift
import Foundation
import Observation
#if !targetEnvironment(macCatalyst)
import UIKit
#endif

/// The main screen's short-lived notice strip (bridge results, "reopened the completed copy").
/// Shared through the environment so a sheet or the agenda can post one; `ContentView` draws it.
@MainActor @Observable
final class NoticeCenter {
    private(set) var text: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Shows `text` for four seconds and announces it to VoiceOver.
    func show(_ text: String) {
        task?.cancel()
        self.text = text
        #if !targetEnvironment(macCatalyst)
        UIAccessibility.post(notification: .announcement, argument: text)
        #endif
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.text = nil }
        }
    }

    func dismiss() {
        task?.cancel()
        text = nil
    }
}
