import Foundation
import Observation

/// Where the watch keeps the latest snapshot the iPhone pushed (app-target glue implements it).
public protocol WatchSnapshotStore: Sendable {
    func load() -> WatchSnapshot?
    func save(_ snapshot: WatchSnapshot)
}

/// What the watch's Up Next list shows: the iPhone's latest snapshot, nothing read from EventKit.
@MainActor @Observable
public final class WatchAgendaModel {
    public enum State: Equatable {
        case waitingForPhone, accessNeeded(String), noSources, empty, items([WatchSnapshotRow]), failed(String)
    }

    public private(set) var state: State
    public private(set) var updatedAt: Date?
    public var lastError: String? { outbox.lastError }

    @ObservationIgnored private let store: WatchSnapshotStore
    @ObservationIgnored public let outbox: WatchOutbox
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(store: WatchSnapshotStore, outbox: WatchOutbox,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.outbox = outbox
        self.now = now
        if let snapshot = store.load() {
            state = Self.state(for: snapshot)
            updatedAt = snapshot.generatedAt
        } else {
            state = .waitingForPhone
        }
    }

    /// Saves the snapshot and shows it.
    public func receive(_ snapshot: WatchSnapshot) {
        store.save(snapshot)
        state = Self.state(for: snapshot)
        updatedAt = snapshot.generatedAt
    }

    /// True when nothing was received yet or the snapshot is older than `after`.
    public func stale(after: TimeInterval = 3 * 3600) -> Bool {
        guard let updatedAt else { return true }
        return now().timeIntervalSince(updatedAt) > after
    }

    private static func state(for snapshot: WatchSnapshot) -> State {
        switch snapshot.state {
        case .accessNeeded(let message): .accessNeeded(message)
        case .noSources: .noSources
        case .empty: .empty
        case .items: .items(snapshot.rows)
        case .failed(let message): .failed(message)
        }
    }
}
