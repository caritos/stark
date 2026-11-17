// ios/Tests/StarkKitTests/ImportModelTests.swift
import Testing
import Foundation
@testable import StarkKit

@MainActor
private struct FixedDestinations: DefaultDestinations {
    var calendarID: String?
    var listID: String?
}

@Suite("ImportModel")
@MainActor
struct ImportModelTests {
    private let today = DateMath.date(from: "2026-09-01")
    private let soon = DateMath.date(from: "2026-09-02")

    private struct Env {
        let root: URL
        let store: PlannerStore
        let sidecar: ItemSidecar
        let sidecarURL: URL
        let repository: FakeItemRepository
        var docs: URL { root.appendingPathComponent("docs") }
    }

    private func makeFile(_ root: URL) -> PlannerFile {
        PlannerFile(directory: root.appendingPathComponent("docs"), pendingDirectory: root.appendingPathComponent("pending"))
    }

    private func makeEnv() throws -> Env {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("import-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        let store = PlannerStore(file: makeFile(root))
        let range = AgendaWindow.loadRange(around: today)
        store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
        let sidecarURL = root.appendingPathComponent("sidecar.json")
        let repository = FakeItemRepository(calendars: [
            AppleCalendarInfo(id: "C1", title: "Home", accountName: "iCloud", colorHex: nil, isReminderList: false),
            AppleCalendarInfo(id: "L1", title: "Reminders", accountName: "iCloud", colorHex: nil, isReminderList: true),
        ])
        return Env(root: root, store: store, sidecar: ItemSidecar(fileURL: sidecarURL), sidecarURL: sidecarURL,
                   repository: repository)
    }

    private func model(_ env: Env, repository: (any ItemRepository)? = nil,
                       destinations: FixedDestinations = FixedDestinations(calendarID: "C1", listID: "L1"),
                       afterRun: @escaping @MainActor (ImportModel) async -> Void = { _ in }) -> ImportModel {
        let today = self.today
        var model: ImportModel!
        model = ImportModel(store: env.store, sidecar: env.sidecar, repository: repository ?? env.repository,
                            destinations: destinations, now: { today }, calendar: Calendar(identifier: .gregorian),
                            afterRun: { await afterRun(model) })
        return model
    }

    private func previewPlan(_ model: ImportModel) -> ImportPlan? {
        if case .preview(let plan, _) = model.state { return plan }
        return nil
    }

    /// Both a count and an until date: it round-trips through the .ics file, but Apple cannot hold
    /// it (a repeat has one end).
    private func oddRule() -> RecurrenceRule {
        RecurrenceRule(frequency: .weekly, count: 10, until: DateMath.date(from: "2027-01-01"))
    }

    @Test("scan loads every month file before planning")
    func scanLoadsAllMonthsFirst() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        // Written by another store instance: a month far outside the agenda's load range.
        let writer = PlannerStore(file: makeFile(env.root))
        writer.addEvent(Event(id: "far", title: "Far trip", start: DateMath.date(from: "2030-03-10")))
        env.store.addEvent(Event(id: "near", title: "Dentist", start: soon))
        #expect(!env.store.allEvents.contains { $0.id == "far" })

        let model = model(env)
        await model.scan()

        let steps = try #require(previewPlan(model)).steps
        #expect(Set(steps.map(\.localID)) == ["near", "far"])
    }

    @Test("an unreadable month aborts the scan with the error; no preview from partial data")
    func unreadableMonthAbortsScan() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        env.store.addEvent(Event(id: "near", title: "Dentist", start: soon))
        try Data([0xFF, 0xFE, 0xC0, 0x80]).write(to: env.docs.appendingPathComponent("2028-01.ics"))

        let model = model(env)
        await model.scan()

        guard case .failed(let message) = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
        #expect(message.contains("2028-01.ics"))
    }

    @Test("an unreadable recurring.ics aborts the scan")
    func unreadableRecurringAbortsScan() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        try Data([0xFF, 0xFE, 0xC0, 0x80]).write(to: env.docs.appendingPathComponent("recurring.ics"))
        let store = PlannerStore(file: makeFile(env.root))
        let range = AgendaWindow.loadRange(around: today)
        store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
        let fresh = Env(root: env.root, store: store, sidecar: env.sidecar, sidecarURL: env.sidecarURL,
                        repository: env.repository)

        let model = model(fresh)
        await model.scan()

        guard case .failed(let message) = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
        #expect(message.contains("recurring"))
    }

    @Test("an unreadable sidecar aborts the scan")
    func unreadableSidecarAbortsScan() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        env.store.addEvent(Event(id: "near", title: "Dentist", start: soon))
        try FileManager.default.createDirectory(at: env.sidecarURL, withIntermediateDirectories: true)

        let model = model(env)
        await model.scan()

        guard case .failed = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
        #expect(model.showsSettingsRow)
    }

    @Test("confirm runs the plan, publishes progress, hides the imported items and ignores a second confirm")
    func confirmRunsAndPublishesProgress() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        env.store.addEvent(Event(id: "e1", title: "Dentist", start: soon))
        env.store.addReminder(Reminder(id: "r1", title: "Call", dueDate: soon))

        let model = model(env)
        await model.scan()
        #expect(previewPlan(model)?.steps.count == 2)

        async let first: Void = model.confirm()
        async let second: Void = model.confirm()
        _ = await (first, second)

        guard case .finished(let result) = model.state else {
            Issue.record("expected .finished, got \(model.state)")
            return
        }
        #expect(result.imported.sorted() == ["e1", "r1"])
        #expect(await env.repository.itemCount == 2)
        #expect(model.lastProgress.done == 2 && model.lastProgress.total == 2)
        #expect(!model.isRunning)
        #expect(env.store.events.isEmpty && env.store.reminders.isEmpty)
        #expect(env.store.importedIDs == ["e1", "r1"])
        #expect(try await env.sidecar.load().importedAt != nil)
        #expect(!model.showsSettingsRow)
    }

    @Test("nothing to import: an empty preview, the import is marked finished and the Settings row goes away")
    func nothingToImportState() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let model = model(env)
        #expect(model.showsSettingsRow)
        await model.scan()

        let plan = try #require(previewPlan(model))
        #expect(plan.isEmpty)
        #expect(try await env.sidecar.load().importedAt == today)
        #expect(!model.showsSettingsRow)
        // Confirming an empty plan creates nothing.
        await model.confirm()
        #expect(await env.repository.itemCount == 0)
    }

    @Test("a retry after a partial failure plans only what is not ledgered")
    func retryAfterFailureOnlyPlansTheRest() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        env.store.addEvent(Event(id: "e1", title: "Dentist", start: soon))
        env.store.addReminder(Reminder(id: "r1", title: "Call", dueDate: soon))

        let model = model(env)
        await model.scan()
        await env.repository.failNext()   // events go first: "Dentist" fails
        await model.confirm()
        guard case .finished(let result) = model.state else {
            Issue.record("expected .finished, got \(model.state)")
            return
        }
        #expect(result.failed.map(\.title) == ["Dentist"])
        #expect(try await env.sidecar.load().importedAt == nil)
        #expect(model.showsSettingsRow)

        await model.scan()
        #expect(previewPlan(model)?.steps.map(\.localID) == ["e1"])
        await model.confirm()
        #expect(await env.repository.itemCount == 2)
        #expect(!model.showsSettingsRow)
    }

    @Test("unrepresentable items get the mark and keep the Settings row; the launch refresh recomputes both")
    func unrepresentableItemsKeepTheMarkAndTheRow() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        env.store.addReminder(Reminder(id: "odd", title: "Odd one", dueDate: soon, recurrence: oddRule()))
        env.store.addEvent(Event(id: "e1", title: "Dentist", start: soon))

        let model = model(env)
        await model.scan()
        #expect(previewPlan(model)?.unrepresentable.map(\.localID) == ["odd"])
        #expect(env.store.notImportedIDs == ["odd"])
        await model.confirm()
        #expect(model.showsSettingsRow)          // the leftover is still listed there
        #expect(model.lastPlan?.unrepresentable.map(\.title) == ["Odd one"])

        // A relaunch: a fresh store and model know nothing until `refreshStatus`.
        let store = PlannerStore(file: makeFile(env.root))
        let range = AgendaWindow.loadRange(around: today)
        store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
        let relaunched = Env(root: env.root, store: store, sidecar: ItemSidecar(fileURL: env.sidecarURL),
                             sidecarURL: env.sidecarURL, repository: env.repository)
        let again = self.model(relaunched)
        await again.refreshStatus()
        #expect(store.importedIDs == ["e1"])
        #expect(store.notImportedIDs == ["odd"])
        #expect(store.events.isEmpty)
        #expect(again.showsSettingsRow)
    }

    @Test("a missing destination refuses before anything is created")
    func missingDestinationRefusesConfirm() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        env.store.addEvent(Event(id: "e1", title: "Dentist", start: soon))

        let model = model(env, destinations: FixedDestinations(calendarID: nil, listID: "L1"))
        await model.scan()
        guard case .preview(_, let destinations) = model.state else {
            Issue.record("expected .preview, got \(model.state)")
            return
        }
        #expect(destinations.problem != nil)
        #expect(destinations.list?.title == "Reminders")
        #expect(destinations.list?.accountName == "iCloud")
        await model.confirm()
        #expect(await env.repository.itemCount == 0)
        if case .preview = model.state {} else { Issue.record("expected to stay on .preview, got \(model.state)") }
    }

    @Test("cancel outside a run returns to idle")
    func cancelReturnsToIdle() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let model = model(env)
        await model.scan()
        model.cancel()
        if case .idle = model.state {} else { Issue.record("expected .idle, got \(model.state)") }
    }

    @Test("afterRun reloads Apple data once the run created something, after the result is shown")
    func afterRunIsCalledAfterARunThatCreatedItems() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        env.store.addEvent(Event(id: "e1", title: "Dentist", start: soon))
        var calls: [(finished: Bool, hidden: Bool)] = []
        let model = model(env, afterRun: { model in
            var finished = false
            if case .finished = model.state { finished = true }
            calls.append((finished, env.store.events.isEmpty))
        })
        await model.scan()
        await model.confirm()
        #expect(calls.count == 1)
        #expect(calls.first?.finished == true)
        #expect(calls.first?.hidden == true)
    }

    @Test("afterRun is not called for a run that created nothing")
    func afterRunIsSkippedWhenNothingWasCreated() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        env.store.addEvent(Event(id: "e1", title: "Dentist", start: soon))
        var calls = 0
        let model = model(env, afterRun: { _ in calls += 1 })
        await model.scan()
        await env.repository.failNext()   // the only step fails
        await model.confirm()
        guard case .finished(let result) = model.state else {
            Issue.record("expected .finished, got \(model.state)")
            return
        }
        #expect(result.imported.isEmpty)
        #expect(calls == 0)
    }
}
