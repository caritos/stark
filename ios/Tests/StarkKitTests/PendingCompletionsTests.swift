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

    // MARK: - Against a real PlannerStore

    @MainActor
    private func makeStore() -> PlannerStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = PlannerFile(directory: root.appendingPathComponent("docs"), pendingDirectory: root.appendingPathComponent("pending"))
        let store = PlannerStore(file: file)
        let range = AgendaWindow.loadRange(around: Date())
        store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
        return store
    }

    @MainActor
    private func pendingBackedBy(_ store: PlannerStore, _ scheduler: ManualScheduler) -> PendingCompletions {
        PendingCompletions(schedule: scheduler.schedule, commit: { store.completeReminder(id: $0, on: $1) })
    }

    @Test("a one-off reminder is completed after the timer fires and not before")
    @MainActor
    func oneOffCompletesOnlyAfterTimer() throws {
        let store = makeStore()
        let scheduler = ManualScheduler()
        let pending = pendingBackedBy(store, scheduler)
        let due = Date()
        store.addReminder(Reminder(id: "rem-1", title: "Buy milk", dueDate: due))

        pending.toggle(key: "k", reminderID: "rem-1", occurrence: due)
        let before = try #require(store.reminders.first { $0.id == "rem-1" })
        #expect(!before.isCompleted)

        scheduler.fire(0)
        let done = try #require(store.reminders.first { $0.id == "rem-1" })
        #expect(done.isCompleted)
        #expect(done.completedDate == due)
    }

    @Test("a reminder deleted while pending is silently skipped when the timer fires")
    @MainActor
    func deletedWhilePendingIsANoOp() {
        let store = makeStore()
        let scheduler = ManualScheduler()
        let pending = pendingBackedBy(store, scheduler)
        let due = Date()
        store.addReminder(Reminder(id: "rem-1", title: "Buy milk", dueDate: due))
        pending.toggle(key: "k", reminderID: "rem-1", occurrence: due)

        store.deleteReminder(id: "rem-1")
        scheduler.fire(0)

        #expect(store.reminders.isEmpty)
        #expect(store.events.isEmpty)
        #expect(store.error == nil)
        #expect(!pending.isPending("k"))
    }

    @Test("flushing pending completions writes them to the store")
    @MainActor
    func flushCompletesInStore() throws {
        let store = makeStore()
        let scheduler = ManualScheduler()
        let pending = pendingBackedBy(store, scheduler)
        let due = Date()
        store.addReminder(Reminder(id: "rem-1", title: "Buy milk", dueDate: due))
        pending.toggle(key: "k", reminderID: "rem-1", occurrence: due)

        pending.flush()

        let flushed = try #require(store.reminders.first { $0.id == "rem-1" })
        #expect(flushed.isCompleted)
        scheduler.fireAll()
        #expect(store.reminders.filter(\.isCompleted).count == 1)
    }

    @Test("a pending completion that fires after Done resolved the same recurring occurrence completes nothing more")
    @MainActor
    func commitAfterDoneOnSameOccurrenceIsIdempotent() throws {
        let store = makeStore()
        let scheduler = ManualScheduler()
        let pending = pendingBackedBy(store, scheduler)
        let due = Date()
        store.addReminder(Reminder(id: "rem-rec", title: "Trash", dueDate: due, recurrence: RecurrenceRule(frequency: .weekly)))
        pending.toggle(key: "k", reminderID: "rem-rec", occurrence: due)

        // Done in the detail sheet resolves the occurrence while the checkbox is still pending.
        store.completeReminder(id: "rem-rec", on: due)
        scheduler.fire(0)

        #expect(store.reminders.filter(\.isCompleted).count == 1)
        let master = try #require(store.reminders.first { $0.id == "rem-rec" })
        #expect(master.exceptionDates.count == 1)
    }

    @Test("a pending completion that fires after Skip resolved the same recurring occurrence makes no completed copy")
    @MainActor
    func commitAfterSkipOnSameOccurrenceMakesNoCopy() throws {
        let store = makeStore()
        let scheduler = ManualScheduler()
        let pending = pendingBackedBy(store, scheduler)
        let due = Date()
        store.addReminder(Reminder(id: "rem-rec", title: "Trash", dueDate: due, recurrence: RecurrenceRule(frequency: .weekly)))
        pending.toggle(key: "k", reminderID: "rem-rec", occurrence: due)

        store.skipReminder(id: "rem-rec", on: due)
        scheduler.fire(0)

        #expect(store.reminders.filter(\.isCompleted).isEmpty)
        let master = try #require(store.reminders.first { $0.id == "rem-rec" })
        #expect(master.exceptionDates.count == 1)
    }

    @Test("completing a missed weekly occurrence through a pending completion clears the earlier misses")
    @MainActor
    func weeklyMissedCompletionClearsEarlierMisses() throws {
        let store = makeStore()
        let scheduler = ManualScheduler()
        let pending = pendingBackedBy(store, scheduler)

        // Weekly at 09:30, first due exactly 28 days before today: -28/-21/-14/-7 days are all
        // missed (today's own 09:30 is not, overdue is day-granular), whatever today is.
        let cal = Calendar(identifier: .gregorian)
        let todayStart = cal.startOfDay(for: Date())
        let first = try #require(cal.date(bySettingHour: 9, minute: 30, second: 0, of: cal.date(byAdding: .day, value: -28, to: todayStart)!))
        let latestMiss = try #require(cal.date(byAdding: .day, value: 21, to: first))
        store.addReminder(Reminder(id: "rem-w", title: "Weekly review", dueDate: first, recurrence: RecurrenceRule(frequency: .weekly)))

        pending.toggle(key: "k", reminderID: "rem-w", occurrence: latestMiss)
        scheduler.fire(0)

        let master = try #require(store.reminders.first { $0.id == "rem-w" })
        // The latest miss plus the three earlier ones are all exdated.
        #expect(master.exceptionDates.count == 4)
        #expect(store.reminders.filter(\.isCompleted).count == 1)
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
