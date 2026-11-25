//
//  SnapshotStore.swift
//  StarkWatch
//
//  Keeps the latest snapshot the iPhone pushed, as JSON in UserDefaults, so the list shows at
//  launch before the phone answers. (Complications will read it from a watch-side App Group in a
//  later task; moving it there is a change of the suite name only.)
//

import Foundation
import os
import StarkKit

nonisolated struct UserDefaultsSnapshotStore: WatchSnapshotStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private static let log = Logger(subsystem: "com.caritos.todo-txt.watchkitapp", category: "snapshot")
    private let key = "watch.snapshot.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

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
        }
    }
}
