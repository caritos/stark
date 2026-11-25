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

    /// Falls back to the app's own defaults if the group container is unavailable (an unsigned or
    /// unregistered build), so the list still works; the complications then show "Open Stark".
    init(defaults: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard) { self.defaults = defaults }

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
