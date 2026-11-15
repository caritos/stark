// ios/Sources/StarkKit/Planner/PendingCompletions.swift
import Foundation
import Combine

/// Schedules `action` to run on the main actor after `delay` seconds and returns a closure that
/// cancels it. Injected so tests can advance time by hand instead of waiting.
public typealias PendingScheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> (@MainActor () -> Void)

/// The agenda checkbox's undo window: tapping an incomplete reminder's checkbox makes it *look*
/// complete right away but only commits the completion after `delay` (2.5s), and tapping it again
/// inside that window cancels. Mirrors the Expo app's `usePendingDone`.
///
/// Deliberately decoupled from `PlannerStore` and `AgendaItem`: it only knows an opaque `key`
/// (the row's stable identity, never a list position — a delete or edit while a timer runs must
/// not be able to complete the wrong item) and the `(reminderID, occurrence)` to hand to `commit`
/// when the window closes. `commit` for a reminder that no longer exists is the store's no-op.
///
/// JS timers in the Expo app don't survive backgrounding and neither does this one, so the app
/// calls `flush()` whenever it leaves the foreground and when the agenda goes away: pending
/// completions are committed immediately, never dropped.
@MainActor
public final class PendingCompletions: ObservableObject {
    /// Keys whose completion is pending (shown as complete, not yet written).
    @Published public private(set) var pendingKeys: Set<String> = []

    private struct Entry {
        let reminderID: String
        let occurrence: Date
        /// Distinguishes this pending completion from an earlier one on the same key, so a stale
        /// timer (cancelled, flushed, or already fired) can never commit a newer one — or commit
        /// twice — even if its scheduler runs it anyway.
        let token: UUID
        /// Start order, so `flush()` commits in the order the user tapped.
        let sequence: Int
        let cancel: @MainActor () -> Void
    }

    private enum Committer {
        case sync(@MainActor (_ reminderID: String, _ occurrence: Date) -> Void)
        case async(@MainActor (_ reminderID: String, _ occurrence: Date) async -> Void)
    }

    private let delay: TimeInterval
    private let schedule: PendingScheduler
    private let committer: Committer
    private var entries: [String: Entry] = [:]
    private var nextSequence = 0
    /// Keys whose async commit has started but not returned: still shown as done, and a tap on
    /// them starts nothing (it would complete the same occurrence twice).
    private var committing: Set<String> = []

    public init(
        delay: TimeInterval = 2.5,
        schedule: @escaping PendingScheduler = PendingCompletions.liveScheduler,
        commit: @escaping @MainActor (_ reminderID: String, _ occurrence: Date) -> Void
    ) {
        self.delay = delay
        self.schedule = schedule
        self.committer = .sync(commit)
    }

    /// As `init(delay:schedule:commit:)`, for a commit that writes asynchronously (`ItemRouter`):
    /// the key stays pending until `asyncCommit` returns, so the row never flashes back to
    /// incomplete before the write (and the reload after it) has landed.
    public init(
        delay: TimeInterval = 2.5,
        schedule: @escaping PendingScheduler = PendingCompletions.liveScheduler,
        asyncCommit: @escaping @MainActor (_ reminderID: String, _ occurrence: Date) async -> Void
    ) {
        self.delay = delay
        self.schedule = schedule
        self.committer = .async(asyncCommit)
    }

    /// Runs the action on the main actor after `delay` seconds; cancelling stops it.
    public nonisolated static let liveScheduler: PendingScheduler = { delay, action in
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }

    public func isPending(_ key: String) -> Bool {
        entries[key] != nil || committing.contains(key)
    }

    /// Starts a pending completion for `key`, or cancels it if one is already pending.
    public func toggle(key: String, reminderID: String, occurrence: Date) {
        guard !committing.contains(key) else { return }
        if let existing = entries.removeValue(forKey: key) {
            existing.cancel()
            pendingKeys.remove(key)
            return
        }

        let token = UUID()
        let cancel = schedule(delay) { [weak self] in
            self?.timerFired(key: key, token: token)
        }
        entries[key] = Entry(reminderID: reminderID, occurrence: occurrence, token: token, sequence: nextSequence, cancel: cancel)
        nextSequence += 1
        pendingKeys.insert(key)
    }

    /// Commits every pending completion now, in tap order, and cancels their timers.
    public func flush() {
        let flushing = entries.sorted { $0.value.sequence < $1.value.sequence }
        guard !flushing.isEmpty else { return }
        entries.removeAll()
        for (_, entry) in flushing { entry.cancel() }
        switch committer {
        case .sync(let commit):
            for (_, entry) in flushing { commit(entry.reminderID, entry.occurrence) }
            pendingKeys.removeAll()
        case .async(let commit):
            let keys = flushing.map(\.key)
            committing.formUnion(keys)
            Task { @MainActor [weak self] in
                // One after another, in tap order.
                for (_, entry) in flushing { await commit(entry.reminderID, entry.occurrence) }
                self?.finishCommitting(keys)
            }
        }
    }

    private func finishCommitting(_ keys: [String]) {
        for key in keys {
            committing.remove(key)
            if entries[key] == nil { pendingKeys.remove(key) }
        }
    }

    private func timerFired(key: String, token: UUID) {
        guard let entry = entries[key], entry.token == token else { return }
        entries[key] = nil
        // Commit before clearing the pending flag (as the Expo hook does), so the row goes
        // straight from "pending" to "committed" with no frame of looking incomplete in between.
        switch committer {
        case .sync(let commit):
            commit(entry.reminderID, entry.occurrence)
            pendingKeys.remove(key)
        case .async(let commit):
            committing.insert(key)
            Task { @MainActor [weak self] in
                await commit(entry.reminderID, entry.occurrence)
                self?.finishCommitting([key])
            }
        }
    }
}
