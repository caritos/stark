//
//  SnapshotStore.swift
//  StarkWatch
//
//  Keeps the latest snapshot the iPhone pushed, as JSON in UserDefaults, so the list shows at
//  launch before the phone answers. (Complications will read it from a watch-side App Group in a
//  later task; moving it there is a change of the suite name only.)
//

import Foundation
import StarkKit

nonisolated struct UserDefaultsSnapshotStore: WatchSnapshotStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "watch.snapshot.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> WatchSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? WatchLinkCoding.decode(WatchSnapshot.self, from: data)
    }

    func save(_ snapshot: WatchSnapshot) {
        guard let data = try? WatchLinkCoding.encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
