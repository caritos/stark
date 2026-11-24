import Foundation
import Observation

/// Keeps the envelopes still waiting for the phone (with the time each was queued), so they
/// survive a relaunch of the watch app.
public protocol WatchPendingStore: Sendable {
    func load() -> [WatchEnvelope: Date]
    func save(_ pending: [WatchEnvelope: Date])
}

/// The waiting envelopes as JSON in UserDefaults. An unreadable value loads as empty.
public struct UserDefaultsWatchPendingStore: WatchPendingStore, @unchecked Sendable {
    private struct Entry: Codable {
        let envelope: WatchEnvelope
        let queuedAt: Date
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "watch.pending.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [WatchEnvelope: Date] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [:] }
        return Dictionary(entries.map { ($0.envelope, $0.queuedAt) }, uniquingKeysWith: { first, _ in first })
    }

    public func save(_ pending: [WatchEnvelope: Date]) {
        let entries = pending.map { Entry(envelope: $0.key, queuedAt: $0.value) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}

/// The watch side of the link: sends a command live when the phone is reachable, else (or when the
/// live send fails) queues it, and tracks each one until the phone's reply arrives.
///
/// At most `maxWaiting` envelopes wait at once: past that a new one is refused with `lastError`
/// set, never dropped silently. One waiting longer than `maxAge` is shown as failed ("Not
/// delivered") by `expireOld()`; a reply arriving later still updates it.
@MainActor @Observable
public final class WatchOutbox {
    public enum Status: Equatable {
        case sending, waiting, done(WatchReply), failed(String)
    }

    public static let notDelivered = "Not delivered"
    public static let fullMessage = "20 items are waiting for your iPhone. Open Stark on your iPhone, then try again."

    public private(set) var statuses: [UUID: Status] = [:]
    public private(set) var lastError: String?

    @ObservationIgnored private let transport: WatchTransport
    @ObservationIgnored private let pendingStore: WatchPendingStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let maxWaiting: Int
    @ObservationIgnored private let maxAge: TimeInterval
    /// Waiting envelopes and when each was queued (mirrored to `pendingStore`).
    @ObservationIgnored private var waiting: [WatchEnvelope: Date]

    public init(transport: WatchTransport, pending: WatchPendingStore,
                now: @escaping @Sendable () -> Date = Date.init, maxWaiting: Int = 20,
                maxAge: TimeInterval = 7 * 24 * 3600) {
        self.transport = transport
        self.pendingStore = pending
        self.now = now
        self.maxWaiting = maxWaiting
        self.maxAge = maxAge
        let loaded = pending.load()
        self.waiting = loaded
        for envelope in loaded.keys { statuses[envelope.id] = .waiting }
    }

    /// Sends the command. Nil (and `lastError` set) when `maxWaiting` envelopes are already waiting.
    @discardableResult
    public func submit(_ command: WatchCommand) async -> UUID? {
        expireOld()
        guard waiting.count < maxWaiting else {
            lastError = Self.fullMessage
            return nil
        }
        lastError = nil
        let envelope = WatchEnvelope(id: UUID(), sentAt: now(), command: command)
        statuses[envelope.id] = .sending
        if transport.isReachable {
            do {
                let reply = try await transport.send(envelope)
                record(reply, for: envelope.id)
                return envelope.id
            } catch {
                // Not delivered live: queue it. If the phone did get it, its id makes the queued
                // copy a no-op there.
            }
            // A reply may have landed through `receive` while the live send was failing.
            guard statuses[envelope.id] == .sending else { return envelope.id }
        }
        waiting[envelope] = now()
        pendingStore.save(waiting)
        transport.queue(envelope)
        statuses[envelope.id] = .waiting
        return envelope.id
    }

    /// A reply from the phone (live or queued). Ignored for an id this outbox never sent.
    public func receive(_ reply: WatchReplyEnvelope) {
        guard statuses[reply.id] != nil else { return }
        record(reply.reply, for: reply.id)
    }

    /// Waiting envelopes queued more than `maxAge` ago become `.failed("Not delivered")` and stop
    /// counting toward the limit.
    public func expireOld() {
        let cutoff = now().addingTimeInterval(-maxAge)
        let expired = waiting.filter { $0.value < cutoff }.map(\.key)
        guard !expired.isEmpty else { return }
        for envelope in expired {
            waiting[envelope] = nil
            statuses[envelope.id] = .failed(Self.notDelivered)
        }
        pendingStore.save(waiting)
    }

    private func record(_ reply: WatchReply, for id: UUID) {
        switch reply {
        case .done: statuses[id] = .done(reply)
        case .failed(let message): statuses[id] = .failed(message)
        }
        if let envelope = waiting.keys.first(where: { $0.id == id }) {
            waiting[envelope] = nil
            pendingStore.save(waiting)
        }
    }
}
