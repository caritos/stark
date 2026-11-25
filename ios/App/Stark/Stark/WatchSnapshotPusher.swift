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
import OSLog
import StarkKit
import WatchConnectivity

nonisolated final class WatchSnapshotPusher: WatchSnapshotPublisher, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.caritos.todo-txt", category: "WatchSnapshot")
    private let provider: AppleItemProvider
    private var observer: NSObjectProtocol?
    private var coalescer: BuildCoalescer!

    init(provider: AppleItemProvider) {
        self.provider = provider
        coalescer = BuildCoalescer { [weak self] in await self?.pushNow() }
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

    /// Builds and pushes a snapshot soon: coalesced, and builds never overlap (`BuildCoalescer`).
    func request() {
        guard WCSession.isSupported() else { return }
        coalescer.request()
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
        guard canPush else { return }
        do {
            let data = try WatchLinkCoding.encode(snapshot)
            try WCSession.default.updateApplicationContext([WatchLinkCoding.snapshotKey: data])
        } catch {
            Self.log.error("Couldn't push the watch snapshot: \(String(describing: error), privacy: .public)")
        }
    }
}
