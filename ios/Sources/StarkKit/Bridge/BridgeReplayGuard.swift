import Foundation

/// Persistence for recently imported batch ids (oldest first).
public protocol ReplayStore: AnyObject {
    func load() -> [String]
    func save(_ ids: [String])
}

public final class InMemoryReplayStore: ReplayStore {
    private var ids: [String] = []
    public init() {}
    public func load() -> [String] { ids }
    public func save(_ ids: [String]) { self.ids = ids }
}

public final class UserDefaultsReplayStore: ReplayStore {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "bridge.recentBatchIDs") {
        self.defaults = defaults
        self.key = key
    }
    public func load() -> [String] { defaults.stringArray(forKey: key) ?? [] }
    public func save(_ ids: [String]) { defaults.set(ids, forKey: key) }
}

public enum ReplayDecision: Equatable, Sendable { case accept, expired, fromFuture, duplicate }

/// Rejects stale, future-dated and already-imported batches. Used from the main actor only,
/// so it does no locking.
public final class BridgeReplayGuard {
    private let store: ReplayStore
    private let now: () -> Date
    private let maxAge: TimeInterval
    private let maxFuture: TimeInterval
    private let capacity: Int

    public init(store: ReplayStore, now: @escaping () -> Date, maxAge: TimeInterval = 600,
                maxFuture: TimeInterval = 120, capacity: Int = 200) {
        self.store = store
        self.now = now
        self.maxAge = maxAge
        self.maxFuture = maxFuture
        self.capacity = capacity
    }

    /// Pure: records nothing.
    public func check(_ batch: BridgeBatch) -> ReplayDecision {
        guard batch.issuedAt.isFinite else { return .expired }
        let age = now().timeIntervalSince1970 - batch.issuedAt
        if age < -maxFuture { return .fromFuture }
        if age > maxAge { return .expired }
        if store.load().contains(batch.batch) { return .duplicate }
        return .accept
    }

    /// Call only after a successful import.
    public func record(_ batch: BridgeBatch) {
        var ids = store.load().filter { $0 != batch.batch }
        ids.append(batch.batch)
        if ids.count > capacity { ids.removeFirst(ids.count - capacity) }
        store.save(ids)
    }
}
