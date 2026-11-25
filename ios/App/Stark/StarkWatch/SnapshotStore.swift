//
//  SnapshotStore.swift
//  StarkWatch
//
//  Keeps the latest snapshot the iPhone pushed, as JSON in the watch-side App Group's UserDefaults,
//  so the list shows at launch before the phone answers and the complications (a separate
//  extension, which compiles this file too) read the same value. Saving reloads their timelines.
//

import Foundation
import os
import StarkKit
import WidgetKit

nonisolated struct UserDefaultsSnapshotStore: WatchSnapshotStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private static let log = Logger(subsystem: "com.caritos.todo-txt.watchkitapp", category: "snapshot")
    private let key = "watch.snapshot.v1"

    /// The watch-side App Group shared by the watch app and its widget extension (not the iPhone's).
    static let appGroup = "group.com.caritos.todo-txt.watch"

    /// The group's defaults when its container can be opened. `UserDefaults(suiteName:)` returns an
    /// object even for a group that is unregistered or missing from the entitlements (then app and
    /// extension would each get a private suite and the complications would never see a snapshot),
    /// so the container is checked first. When it cannot be opened this logs an error and uses the
    /// app's own defaults: the list still works, the complications stay on "Open Stark on iPhone".
    /// Glue only (needs the signed entitlement), so not unit-tested.
    static func groupDefaults() -> UserDefaults {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil,
              let defaults = UserDefaults(suiteName: appGroup) else {
            log.error("App Group \(appGroup, privacy: .public) has no container: complications will not see snapshots")
            return .standard
        }
        return defaults
    }

    init(defaults: UserDefaults = UserDefaultsSnapshotStore.groupDefaults()) { self.defaults = defaults }

    func load() -> WatchSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do { return try WatchLinkCoding.decode(WatchSnapshot.self, from: data) } catch {
            Self.log.error("snapshot decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ snapshot: WatchSnapshot) {
        do { defaults.set(try WatchLinkCoding.encode(snapshot), forKey: key) } catch {
            Self.log.error("snapshot encode failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
