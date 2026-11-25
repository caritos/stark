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

    /// What the list shows: the snapshot's rows minus any row being completed.
    public var state: State {
        guard case .items(let rows) = base else { return base }
        let shown = rows.filter { !isCompleting($0) }
        return shown.isEmpty ? .empty : .items(shown)
    }
    private var base: State
    public private(set) var updatedAt: Date?
    /// The outbox's refusal (queue full) or the phone's message for a completion that failed.
    public var lastError: String? {
        if let error = outbox.lastError { return error }
        for entry in inFlight.values {
            if let id = entry.envelope, case .failed(let message) = outbox.statuses[id] { return message }
        }
        return nil
    }

    private struct Key: Hashable { let identifier: String; let occurrence: Date }
    private struct InFlight { let row: WatchSnapshotRow; var envelope: UUID? }
    private var inFlight: [Key: InFlight] = [:]

    @ObservationIgnored private let store: WatchSnapshotStore
    @ObservationIgnored public let outbox: WatchOutbox
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(store: WatchSnapshotStore, outbox: WatchOutbox,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.outbox = outbox
        self.now = now
        if let snapshot = store.load() {
            base = Self.state(for: snapshot)
            updatedAt = snapshot.generatedAt
        } else {
            base = .waitingForPhone
        }
    }

    /// Saves the snapshot and shows it. One older than the one shown is ignored (a live message
    /// and the application context can arrive out of order); an equal time is accepted.
    public func receive(_ snapshot: WatchSnapshot) {
        if let updatedAt, snapshot.generatedAt < updatedAt { return }
        store.save(snapshot)
        base = Self.state(for: snapshot)
        updatedAt = snapshot.generatedAt
        // A finished completion is forgotten once a snapshot no longer lists the row.
        let listed = Set(snapshot.rows.compactMap(Self.key))
        for (key, entry) in inFlight {
            guard let id = entry.envelope, !listed.contains(key) else { continue }
            if case .done = outbox.statuses[id] { inFlight[key] = nil }
        }
    }

    private static func key(_ row: WatchSnapshotRow) -> Key? {
        guard row.item.isReminder, let id = row.reminderIdentifier, let occurrence = row.occurrence else { return nil }
        return Key(identifier: id, occurrence: occurrence)
    }

    private func isCompleting(_ row: WatchSnapshotRow) -> Bool {
        guard let key = Self.key(row), let entry = inFlight[key] else { return false }
        guard let id = entry.envelope else { return true }
        if case .failed = outbox.statuses[id] { return false }
        return true
    }

    /// Rows whose completion the iPhone has not answered yet (hidden from `state`).
    public var waitingRows: [WatchSnapshotRow] {
        inFlight.values.compactMap { entry in
            guard let id = entry.envelope, outbox.statuses[id] == .waiting else { return nil }
            return entry.row
        }.sorted { ($0.item.start ?? .distantPast) < ($1.item.start ?? .distantPast) }
    }

    public func waiting(_ row: WatchSnapshotRow) -> Bool {
        guard let key = Self.key(row), let id = inFlight[key]?.envelope else { return false }
        return outbox.statuses[id] == .waiting
    }

    /// Completes a reminder through the iPhone: the row leaves the list at once and comes back if
    /// the phone reports a failure. Events and a row already being completed are ignored.
    public func complete(_ row: WatchSnapshotRow) async {
        guard let key = Self.key(row), let identifier = row.reminderIdentifier,
              let occurrence = row.occurrence, !isCompleting(row) else { return }
        inFlight[key] = InFlight(row: row, envelope: nil)
        let id = await outbox.submit(.complete(identifier: identifier, externalID: row.externalID, occurrence: occurrence))
        if id == nil { inFlight[key] = nil } else { inFlight[key]?.envelope = id }
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
