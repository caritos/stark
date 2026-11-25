//
//  WatchSnapshotPusher.swift
//  Stark
//
//  Pushes the watch's Up Next snapshot (StarkKit `WatchSnapshotBuilder`, tested there) with
//  `WCSession.updateApplicationContext` (latest wins). The watch reads nothing from EventKit. Only
//  this glue touches WatchConnectivity.
//
//  Triggers (all through `request()`): launch, scene active, `EKEventStoreChanged`, a write
//  (watch command or the phone's own), session activation and the watch's snapshot request.
//  Requests coalesce: at most one build per second. Does nothing without a paired watch with the
//  app installed or before the session is activated.
//

import EventKit
import Foundation
import StarkKit
import WatchConnectivity

nonisolated final class WatchSnapshotPusher: WatchSnapshotPublisher, @unchecked Sendable {
    private let provider: AppleItemProvider
    private let lock = NSLock()
    private var scheduled = false
    private var observer: NSObjectProtocol?

    init(provider: AppleItemProvider) {
        self.provider = provider
    }

    /// Call once at launch: pushes now and again on every Calendar/Reminders store change.
    func start() {
        guard WCSession.isSupported() else { return }
        if let name = provider.storeChangedNotification {
            observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.request()
            }
        }
        request()
    }

    /// Builds and pushes a snapshot soon (coalesced to one build per second).
    func request() {
        guard WCSession.isSupported() else { return }
        lock.lock()
        if scheduled { lock.unlock(); return }
        scheduled = true
        lock.unlock()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            self.lock.lock()
            self.scheduled = false
            self.lock.unlock()
            await self.pushNow()
        }
    }

    private func pushNow() async {
        guard canPush else { return }
        let excluded = UserDefaults(suiteName: SelectionMirror.suiteName)
            .map(SelectionMirror.excludedIDs(from:)) ?? []
        let snapshot = await WatchSnapshotBuilder.build(provider: provider, now: Date(), excluded: excluded,
                                                        calendar: .autoupdatingCurrent)
        publish(snapshot)
    }

    private var canPush: Bool {
        let session = WCSession.default
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    func publish(_ snapshot: WatchSnapshot) {
        guard canPush, let data = try? WatchLinkCoding.encode(snapshot) else { return }
        try? WCSession.default.updateApplicationContext([WatchLinkCoding.snapshotKey: data])
    }
}
