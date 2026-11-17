// ios/Tests/StarkKitTests/PendingCompletionsTests.swift
import Testing
import Foundation
@testable import StarkKit

/// A scheduler tests advance by hand: nothing here ever waits on real time.
@MainActor
private final class ManualScheduler {
    struct Timer {
        let delay: TimeInterval
        let action: @MainActor () -> Void
        var isCancelled = false
    }

    private(set) var timers: [Timer] = []

    var schedule: PendingScheduler {
        { [self] delay, action in
            let index = timers.count
            timers.append(Timer(delay: delay, action: action))
            return { [self] in timers[index].isCancelled = true }
        }
    }

    /// Fires timer `index` whether or not it was cancelled, so a test can prove a cancelled or
    /// flushed timer that still gets triggered (a scheduler race) can never commit.
    func fire(_ index: Int) {
        timers[index].action()
    }

    func fireAll() {
        for index in timers.indices { fire(index) }
    }
}

@Suite("PendingCompletions")
struct PendingCompletionsTests {
    /// Records every commit and hands back the completions under test.
    @MainActor
    private func make(delay: TimeInterval? = nil) -> (PendingCompletions, ManualScheduler, Recorder) {
        let scheduler = ManualScheduler()
        let recorder = Recorder()
        let commit: @MainActor (String, Date) -> Void = { recorder.commits.append(Commit(id: $0, occurrence: $1)) }
        let pending = delay.map { PendingCompletions(delay: $0, schedule: scheduler.schedule, commit: commit) }
            ?? PendingCompletions(schedule: scheduler.schedule, commit: commit)
        return (pending, scheduler, recorder)
    }

    private let day1 = DateMath.date(from: "2026-09-21")
    private let day2 = DateMath.date(from: "2026-09-22")

    @Test("the default window is 2.5 seconds")
    @MainActor
    func defaultDelayIsTwoAndAHalfSeconds() {
        let (pending, scheduler, _) = make()
        pending.toggle(key: "k", reminderID: "r", occurrence: day1)
        #expect(scheduler.timers.map(\.delay) == [2.5])
    }

    @Test("a custom delay is passed to the scheduler")
    @MainActor
    func customDelayIsUsed() {
        let (pending, scheduler, _) = make(delay: 7)
        pending.toggle(key: "k", reminderID: "r", occurrence: day1)
        #expect(scheduler.timers.map(\.delay) == [7])
    }

    @Test("starting marks the key pending and does not commit before the delay")
    @MainActor
    func startMarksPendingWithoutCommitting() {
        let (pending, _, recorder) = make()
        #expect(!pending.isPending("k"))

        pending.toggle(key: "k", reminderID: "r", occurrence: day1)

        #expect(pending.isPending("k"))
        #expect(pending.pendingKeys == ["k"])
        #expect(recorder.commits.isEmpty)
    }

    @Test("firing the timer commits exactly once with the right reminder and occurrence, and clears pending")
    @MainActor
    func firingCommitsOnce() {
        let (pending, scheduler, recorder) = make()
        pending.toggle(key: "k", reminderID: "rem-1", occurrence: day1)

        scheduler.fire(0)

        #expect(recorder.commits == [Commit(id: "rem-1", occurrence: day1)])
        #expect(!pending.isPending("k"))
        #expect(pending.pendingKeys.isEmpty)

        // The same timer firing again (a scheduler quirk) must not double-commit.
        scheduler.fire(0)
        #expect(recorder.commits.count == 1)
    }

    @Test("toggling again inside the window cancels: nothing is committed, even if the cancelled timer is triggered")
    @MainActor
    func secondToggleCancels() {
        let (pending, scheduler, recorder) = make()
        pending.toggle(key: "k", reminderID: "r", occurrence: day1)

        pending.toggle(key: "k", reminderID: "r", occurrence: day1)

        #expect(!pending.isPending("k"))
        #expect(scheduler.timers[0].isCancelled)
        scheduler.fire(0)
        #expect(recorder.commits.isEmpty)
        #expect(!pending.isPending("k"))
    }

    @Test("flush commits everything pending immediately, clears it, and later timers do not double-commit")
    @MainActor
    func flushCommitsAllNow() {
        let (pending, scheduler, recorder) = make()
        pending.toggle(key: "a", reminderID: "rem-a", occurrence: day1)
        pending.toggle(key: "b", reminderID: "rem-b", occurrence: day2)

        pending.flush()

        #expect(recorder.commits == [Commit(id: "rem-a", occurrence: day1), Commit(id: "rem-b", occurrence: day2)])
        #expect(pending.pendingKeys.isEmpty)
        let allCancelled = scheduler.timers.allSatisfy { $0.isCancelled }
        #expect(allCancelled)

        scheduler.fireAll()
        #expect(recorder.commits.count == 2)
    }

    @Test("flush with nothing pending does nothing")
    @MainActor
    func flushWhenIdle() {
        let (pending, _, recorder) = make()
        pending.flush()
        #expect(recorder.commits.isEmpty)
        #expect(pending.pendingKeys.isEmpty)
    }

    @Test("flush leaves cancelled completions alone")
    @MainActor
    func flushIgnoresCancelled() {
        let (pending, _, recorder) = make()
        pending.toggle(key: "a", reminderID: "rem-a", occurrence: day1)
        pending.toggle(key: "a", reminderID: "rem-a", occurrence: day1) // cancel
        pending.toggle(key: "b", reminderID: "rem-b", occurrence: day2)

        pending.flush()

        #expect(recorder.commits == [Commit(id: "rem-b", occurrence: day2)])
    }

    @Test("two different keys are independent")
    @MainActor
    func keysAreIndependent() {
        let (pending, scheduler, recorder) = make()
        pending.toggle(key: "a", reminderID: "rem-a", occurrence: day1)
        pending.toggle(key: "b", reminderID: "rem-b", occurrence: day2)
        #expect(pending.pendingKeys == ["a", "b"])

        // Cancelling one leaves the other pending.
        pending.toggle(key: "a", reminderID: "rem-a", occurrence: day1)
        #expect(pending.pendingKeys == ["b"])

        // Firing one leaves nothing else touched.
        scheduler.fire(1)
        #expect(recorder.commits == [Commit(id: "rem-b", occurrence: day2)])
        scheduler.fire(0) // the cancelled one
        #expect(recorder.commits.count == 1)
    }

    @Test("toggling a key again after it committed starts a fresh pending")
    @MainActor
    func freshPendingAfterCommit() {
        let (pending, scheduler, recorder) = make()
        pending.toggle(key: "k", reminderID: "r", occurrence: day1)
        scheduler.fire(0)
        #expect(recorder.commits.count == 1)

        pending.toggle(key: "k", reminderID: "r", occurrence: day1)

        #expect(pending.isPending("k"))
        #expect(scheduler.timers.count == 2)
        #expect(recorder.commits.count == 1)
        scheduler.fire(1)
        #expect(recorder.commits.count == 2)
    }

    @Test("a cancelled then restarted key is governed only by the newest timer")
    @MainActor
    func staleTimerCannotCommitARestartedKey() {
        let (pending, scheduler, recorder) = make()
        pending.toggle(key: "k", reminderID: "r", occurrence: day1) // timer 0
        pending.toggle(key: "k", reminderID: "r", occurrence: day1) // cancel
        pending.toggle(key: "k", reminderID: "r", occurrence: day1) // timer 1

        scheduler.fire(0) // stale
        #expect(recorder.commits.isEmpty)
        #expect(pending.isPending("k"))

        scheduler.fire(1)
        #expect(recorder.commits.count == 1)
    }

    @Test("the live scheduler runs an action after its delay, and not once cancelled")
    @MainActor
    func liveSchedulerRunsAndCancels() async throws {
        let live = PendingCompletions.liveScheduler
        var ran: [String] = []
        _ = live(0.02) { ran.append("kept") }
        let cancel = live(0.02) { ran.append("cancelled") }
        cancel()
        #expect(ran.isEmpty)

        try await Task.sleep(nanoseconds: 400_000_000)

        #expect(ran == ["kept"])
    }
}

private struct Commit: Equatable {
    let id: String
    let occurrence: Date
}

@MainActor
private final class Recorder {
    var commits: [Commit] = []
}

/// Task 9a: the commit goes through the async `ItemRouter`, so a row stays "pending" (looks done)
/// until the write has returned; it never flashes back to incomplete in between.
@Suite("PendingCompletions async commit")
struct PendingCompletionsAsyncTests {
    private let day1 = DateMath.date(from: "2026-09-21")
    private let day2 = DateMath.date(from: "2026-09-22")

    /// A commit the test releases by hand.
    @MainActor
    private final class Gate {
        var started: [Commit] = []
        var finished: [Commit] = []
        private var continuations: [CheckedContinuation<Void, Never>] = []

        func commit(_ id: String, _ occurrence: Date) async {
            started.append(Commit(id: id, occurrence: occurrence))
            await withCheckedContinuation { continuations.append($0) }
            finished.append(Commit(id: id, occurrence: occurrence))
        }

        func releaseAll() {
            let waiting = continuations
            continuations = []
            for c in waiting { c.resume() }
        }
    }

    @MainActor
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test("the key stays pending until the async commit returns, then clears")
    @MainActor
    func staysPendingUntilCommitted() async {
        let scheduler = ManualScheduler()
        let gate = Gate()
        let pending = PendingCompletions(schedule: scheduler.schedule, asyncCommit: { await gate.commit($0, $1) })
        pending.toggle(key: "k", reminderID: "r", occurrence: day1)
        scheduler.fire(0)
        await settle()
        #expect(gate.started == [Commit(id: "r", occurrence: day1)])
        #expect(pending.isPending("k"))
        #expect(pending.pendingKeys == ["k"])
        // A second tap while the write is in flight starts nothing new.
        pending.toggle(key: "k", reminderID: "r", occurrence: day1)
        #expect(scheduler.timers.count == 1)
        gate.releaseAll()
        await settle()
        #expect(gate.finished == [Commit(id: "r", occurrence: day1)])
        #expect(!pending.isPending("k"))
        #expect(pending.pendingKeys.isEmpty)
    }

    @Test("flush commits every pending one in tap order; a cancelled one never commits")
    @MainActor
    func flushInOrder() async {
        let scheduler = ManualScheduler()
        let gate = Gate()
        let pending = PendingCompletions(schedule: scheduler.schedule, asyncCommit: { await gate.commit($0, $1) })
        pending.toggle(key: "b", reminderID: "rb", occurrence: day2)
        pending.toggle(key: "a", reminderID: "ra", occurrence: day1)
        pending.toggle(key: "c", reminderID: "rc", occurrence: day1)
        pending.toggle(key: "c", reminderID: "rc", occurrence: day1)
        pending.flush()
        scheduler.fireAll()
        for _ in 0..<3 {
            await settle()
            gate.releaseAll()
        }
        await settle()
        #expect(gate.finished == [Commit(id: "rb", occurrence: day2), Commit(id: "ra", occurrence: day1)])
        #expect(pending.pendingKeys.isEmpty)
    }
}
