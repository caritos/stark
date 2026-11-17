// ios/Tests/StarkKitTests/ImportRunnerTests.swift
import Testing
import Foundation
@testable import StarkKit

/// A repository that wraps the fake and lets a test hook into or fail specific calls.
private actor ScriptedRepository: ItemRepository {
    let inner: FakeItemRepository
    var failTitles: Set<String> = []
    var failOccurrenceDeletes = false
    var failDeletes = false
    var onAdd: (@Sendable (String) async -> Void)?

    init(inner: FakeItemRepository) { self.inner = inner }

    func setFailTitles(_ titles: Set<String>) { failTitles = titles }
    func setFailDeletes(_ value: Bool) { failDeletes = value }
    func setFailOccurrenceDeletes(_ value: Bool) { failOccurrenceDeletes = value }
    func setOnAdd(_ hook: (@Sendable (String) async -> Void)?) { onAdd = hook }

    struct Injected: Error {}

    func addEvent(_ event: NewEvent, calendarID: String) async throws -> AppleItemRef {
        await onAdd?(event.title)
        if failTitles.contains(event.title) { throw Injected() }
        return try await inner.addEvent(event, calendarID: calendarID)
    }
    func addReminder(_ reminder: NewReminder, listID: String) async throws -> AppleItemRef {
        await onAdd?(reminder.title)
        if failTitles.contains(reminder.title) { throw Injected() }
        return try await inner.addReminder(reminder, listID: listID)
    }
    func details(_ ref: AppleItemRef) async throws -> ItemDetails { try await inner.details(ref) }
    func update(_ ref: AppleItemRef, event patch: EventPatch) async throws { try await inner.update(ref, event: patch) }
    func update(_ ref: AppleItemRef, reminder patch: ReminderPatch) async throws { try await inner.update(ref, reminder: patch) }
    func delete(_ ref: AppleItemRef) async throws {
        if failDeletes { throw Injected() }
        try await inner.delete(ref)
    }
    func deleteOccurrence(_ ref: AppleItemRef, on date: Date) async throws {
        if failOccurrenceDeletes { throw Injected() }
        try await inner.deleteOccurrence(ref, on: date)
    }
    func complete(_ ref: AppleItemRef, on date: Date) async throws { try await inner.complete(ref, on: date) }
    func uncomplete(_ ref: AppleItemRef) async throws { try await inner.uncomplete(ref) }
    func writableCalendars() async throws -> [AppleCalendarInfo] { try await inner.writableCalendars() }
    func addBatch(events: [(event: NewEvent, calendarID: String)],
                  reminders: [(reminder: NewReminder, listID: String)]) async throws -> [AppleItemRef] {
        try await inner.addBatch(events: events, reminders: reminders)
    }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}

@Suite struct ImportRunnerTests {
    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let finishedAt = Date(timeIntervalSince1970: 1_800_500_000)

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("runner-\(UUID().uuidString)").appendingPathComponent("sidecar.json")
    }

    private func fake(assignsExternalIDs: Bool = false) -> FakeItemRepository {
        FakeItemRepository(calendars: [
            AppleCalendarInfo(id: "C1", title: "Cal", accountName: "iCloud", colorHex: nil, isReminderList: false),
            AppleCalendarInfo(id: "L1", title: "List", accountName: "iCloud", colorHex: nil, isReminderList: true),
        ], assignsExternalIDs: assignsExternalIDs)
    }

    private func eventStep(_ id: String, _ title: String, exceptions: [Date] = [], repeats: Bool = false,
                           outcomes: [EventOutcomeRecord] = []) -> ImportStep {
        ImportStep(localID: id, kind: .event,
                   event: NewEvent(title: title, start: base, end: base.addingTimeInterval(3600),
                                   recurrence: repeats ? RecurrenceRule(frequency: .daily) : nil),
                   exceptionDates: exceptions, outcomes: outcomes, title: title)
    }

    private func reminderStep(_ id: String, _ title: String, completedAt: Date? = nil,
                              plans: [PlanBlock] = []) -> ImportStep {
        ImportStep(localID: id, kind: .reminder,
                   reminder: NewReminder(title: title, due: base, completedAt: completedAt),
                   plans: plans, title: title)
    }

    private func runner(_ repo: ItemRepository, _ sidecar: ItemSidecar) -> ImportRunner {
        let stamp = finishedAt
        return ImportRunner(repository: repo, sidecar: sidecar, calendarID: "C1", listID: "L1", now: { stamp })
    }

    @Test func importsEveryStepAndLedgersEachBeforeTheNext() async throws {
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc)
        let repo = ScriptedRepository(inner: fake())
        let seen = Box<[Int]>([])
        await repo.setOnAdd { _ in
            // What the ledger holds at the moment step k+1 starts creating.
            let count = (try? await sidecar.importedIDs().count) ?? -1
            seen.value.append(count)
        }
        let plan = ImportPlan(steps: [eventStep("a", "A"), reminderStep("b", "B"), eventStep("c", "C")])
        let result = await runner(repo, sidecar).run(plan, progress: { _, _ in })
        #expect(seen.value == [0, 1, 2])
        #expect(result.imported == ["a", "b", "c"])
        #expect(result.failed.isEmpty && result.needsCheck.isEmpty)
        #expect(result.stoppedBecauseSidecar == nil && !result.cancelled)
        #expect(try await sidecar.importedIDs() == ["a", "b", "c"])
        #expect(try await sidecar.load().importedAt == finishedAt)
    }

    @Test func progressReportsDoneOfTotal() async throws {
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc)
        let calls = Box<[[Int]]>([])
        let plan = ImportPlan(steps: [eventStep("a", "A"), eventStep("b", "B")])
        _ = await runner(fake(), sidecar).run(plan, progress: { calls.value.append([$0, $1]) })
        #expect(calls.value == [[1, 2], [2, 2]])
    }

    @Test func secondRunAddsNothing() async throws {
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc)
        let repo = fake()
        let events = [Event(id: "e1", title: "One", start: base), Event(id: "e2", title: "Two", start: base)]
        let first = ImportPlanner.plan(events: events, reminders: [], plans: [], alreadyImported: [], apple: [],
                                       today: base, calendar: Self.utc)
        _ = await runner(repo, sidecar).run(first, progress: { _, _ in })
        #expect(await repo.itemCount == 2)
        let imported = try await sidecar.importedIDs()
        let again = ImportPlanner.plan(events: events, reminders: [], plans: [], alreadyImported: imported,
                                       apple: [], today: base, calendar: Self.utc)
        #expect(again.isEmpty)
        let result = await runner(repo, sidecar).run(again, progress: { _, _ in })
        #expect(result.imported.isEmpty)
        // Even the stale plan (already-imported ids still in it) creates nothing.
        let stale = await runner(repo, sidecar).run(first, progress: { _, _ in })
        #expect(stale.imported.isEmpty)
        #expect(await repo.itemCount == 2)
    }

    @Test func killAfterNStepsThenRerunAddsOnlyTheRest() async throws {
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc)
        let repo = fake()
        let plan = ImportPlan(steps: (1...5).map { eventStep("e\($0)", "E\($0)") })
        let handle = Box<Task<ImportResult, Never>?>(nil)
        let r = runner(repo, sidecar)
        let task = Task { await r.run(plan, progress: { done, _ in if done == 3 { handle.value?.cancel() } }) }
        handle.value = task
        let first = await task.value
        #expect(first.cancelled)
        #expect(first.imported == ["e1", "e2", "e3"])
        #expect(try await sidecar.load().importedAt == nil)
        #expect(await repo.itemCount == 3)
        let second = await runner(repo, sidecar).run(plan, progress: { _, _ in })
        #expect(second.imported == ["e4", "e5"])
        #expect(!second.cancelled)
        #expect(await repo.itemCount == 5)
        #expect(try await sidecar.load().importedAt != nil)
    }

    @Test func failedStepIsReportedAndRunContinues() async throws {
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc)
        let inner = fake()
        let repo = ScriptedRepository(inner: inner)
        await repo.setFailTitles(["Two"])
        let plan = ImportPlan(steps: [eventStep("1", "One"), eventStep("2", "Two"), eventStep("3", "Three")])
        let result = await runner(repo, sidecar).run(plan, progress: { _, _ in })
        #expect(result.imported == ["1", "3"])
        #expect(result.failed.map(\.title) == ["Two"])
        #expect(!result.failed[0].message.isEmpty)
        #expect(try await sidecar.importedIDs() == ["1", "3"])
        #expect(try await sidecar.load().importedAt == nil)
        await repo.setFailTitles([])
        let retry = await runner(repo, sidecar).run(plan, progress: { _, _ in })
        #expect(retry.imported == ["2"])
        #expect(await inner.itemCount == 3)
        #expect(try await sidecar.load().importedAt != nil)
    }

    @Test func sidecarWriteFailureStopsRunAtOnce() async throws {
        struct Boom: Error {}
        let writes = Box<Int>(0)
        let writer: SidecarWriter = { data, url in
            writes.value += 1
            if writes.value >= 2 { throw Boom() }
            try ItemSidecar.atomicWriter(data, url)
        }
        let url = tempURL()
        let sidecar = ItemSidecar(fileURL: url, calendar: Self.utc, writer: writer)
        let repo = fake()
        let plan = ImportPlan(steps: [eventStep("1", "One"), eventStep("2", "Two"), eventStep("3", "Three")])
        let result = await runner(repo, sidecar).run(plan, progress: { _, _ in })
        #expect(result.imported == ["1"])
        let stopped = try #require(result.stoppedBecauseSidecar)
        // The second item was created in Apple but could not be ledgered: it is named and rolled back
        // (deleted again), the third is never created.
        #expect(stopped.contains("Two"))
        #expect(await repo.itemCount == 1)
        #expect(!result.rollbackFailed && result.canRetry)
        #expect(result.failed.isEmpty)
        #expect(try await ItemSidecar(fileURL: url, calendar: Self.utc).importedIDs() == ["1"])
    }

    @Test func exceptionDeleteFailureStillLedgersAndReportsNeedsCheck() async throws {
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc)
        let repo = ScriptedRepository(inner: fake())
        await repo.setFailOccurrenceDeletes(true)
        let step = eventStep("s", "Standup", exceptions: [base.addingTimeInterval(86_400)], repeats: true)
        let result = await runner(repo, sidecar).run(ImportPlan(steps: [step, eventStep("t", "Later")]),
                                                    progress: { _, _ in })
        #expect(result.imported == ["s", "t"])
        #expect(result.needsCheck == ["Standup"])
        #expect(result.failed.isEmpty)
        #expect(try await sidecar.importedIDs() == ["s", "t"])
    }

    @Test func exceptionDatesAreDeletedAfterTheSeriesIsLedgered() async throws {
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc)
        let inner = fake()
        let day2 = base.addingTimeInterval(86_400)
        let step = eventStep("s", "Standup", exceptions: [day2], repeats: true)
        let result = await runner(inner, sidecar).run(ImportPlan(steps: [step]), progress: { _, _ in })
        #expect(result.needsCheck.isEmpty)
        let id = try #require(try await sidecar.load().importLedger["s"])
        let details = try await inner.details(AppleItemRef(kind: .event, identifier: id))
        #expect(details.event?.exceptionDates == [day2])
    }

    @Test func planBlocksAndOutcomesLandUnderTheAppleIdentifier() async throws {
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc)
        let repo = fake(assignsExternalIDs: true)
        let block = PlanBlock(id: "pb", reminderID: "local-r", occurrence: base, start: base, minutes: 30)
        let outcome = EventOutcomeRecord(date: base, outcome: .skipped)
        let plan = ImportPlan(steps: [reminderStep("local-r", "R", plans: [block]),
                                      eventStep("local-e", "E", outcomes: [outcome])])
        _ = await runner(repo, sidecar).run(plan, progress: { _, _ in })
        let data = try await sidecar.load()
        let rid = try #require(data.importLedger["local-r"])
        let eid = try #require(data.importLedger["local-e"])
        #expect(data.plans.first { $0.id == "pb" }?.reminderID == rid)
        #expect(data.externalIDs[rid] == "ext-\(rid)")
        let entry = try #require(data.outcomes.first { $0.identifier == eid })
        #expect(entry.externalID == "ext-\(eid)")
        #expect(entry.record.outcome == .skipped)
        #expect(data.bridgeLedger["local-r"] == rid)
    }

    @Test func completedOneOffIsCreatedCompleted() async throws {
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc)
        let repo = fake()
        let at = base.addingTimeInterval(500)
        let result = await runner(repo, sidecar).run(ImportPlan(steps: [reminderStep("r", "Done thing", completedAt: at)]),
                                                    progress: { _, _ in })
        #expect(result.imported == ["r"])
        let stored = try #require(await repo.allReminders.first)
        #expect(stored.isCompleted)
        #expect(stored.completedAt == at)
    }

    @Test func unwritableDestinationRefusesBeforeCreatingAnything() async throws {
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc)
        let repo = fake()
        let plan = ImportPlan(steps: [eventStep("a", "A"), reminderStep("b", "B")])
        let bad = ImportRunner(repository: repo, sidecar: sidecar, calendarID: "", listID: "L1")
        let result = await bad.run(plan, progress: { _, _ in })
        #expect(result.imported.isEmpty)
        #expect(result.failed.map(\.title) == ["A", "B"])
        #expect(result.failed.allSatisfy { !$0.message.isEmpty })
        #expect(await repo.itemCount == 0)
        #expect(try await sidecar.importedIDs().isEmpty)
        #expect(try await sidecar.load().importedAt == nil)
    }

    @Test func failedLedgerWriteRollsTheItemBackSoARerunIsClean() async throws {
        struct Boom: Error {}
        let writer: SidecarWriter = { _, _ in throw Boom() }
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc, writer: writer)
        let repo = fake()
        let plan = ImportPlan(steps: [eventStep("1", "One"), reminderStep("2", "Two")])
        let result = await runner(repo, sidecar).run(plan, progress: { _, _ in })
        #expect(await repo.itemCount == 0)
        #expect(result.imported.isEmpty)
        #expect(result.stoppedBecauseSidecar?.contains("One") == true)
        #expect(!result.rollbackFailed && result.canRetry)
    }

    @Test func failedLedgerWriteWithFailedRollbackNamesTheItemAndForbidsRetry() async throws {
        struct Boom: Error {}
        let writer: SidecarWriter = { _, _ in throw Boom() }
        let sidecar = ItemSidecar(fileURL: tempURL(), calendar: Self.utc, writer: writer)
        let repo = ScriptedRepository(inner: fake())
        await repo.setFailDeletes(true)
        let result = await runner(repo, sidecar).run(ImportPlan(steps: [eventStep("1", "One")]), progress: { _, _ in })
        #expect(result.rollbackFailed)
        let stopped = try #require(result.stoppedBecauseSidecar)
        #expect(stopped.contains("One") && stopped.contains("twice"))
        #expect(!result.canRetry)
    }

    @Test func canRetryRule() {
        var result = ImportResult()
        #expect(!result.canRetry)
        result.failed = [(title: "A", message: "x")]
        #expect(result.canRetry)
        result.rollbackFailed = true
        result.stoppedBecauseSidecar = "x"
        #expect(!result.canRetry)
        result = ImportResult()
        result.cancelled = true
        #expect(result.canRetry)
    }
}
