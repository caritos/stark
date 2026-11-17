// ios/Sources/StarkKit/Import/ImportModel.swift
import Foundation
import Observation

/// The preview's destinations: the default calendar and list (with their account, e.g. "iCloud")
/// and why the import cannot start, if it cannot.
public struct ImportDestinations: Equatable, Sendable {
    public var calendar: AppleCalendarInfo?
    public var list: AppleCalendarInfo?
    /// Set when either destination is missing or not writable; the import refuses to start.
    public var problem: String?

    public init(calendar: AppleCalendarInfo?, list: AppleCalendarInfo?, problem: String?) {
        self.calendar = calendar
        self.list = list
        self.problem = problem
    }
}

/// Where the import screen is.
public enum ImportState {
    case idle
    case scanning
    /// A plan to confirm (an empty plan means nothing is left to import).
    case preview(ImportPlan, ImportDestinations)
    case running(done: Int, total: Int)
    case finished(ImportResult)
    /// The scan could not read everything; no plan is shown from partial data.
    case failed(String)
}

/// The "Import Stark's own items" screen's state machine (phase 2 import):
/// `idle -> scanning -> preview -> running -> finished`, with `failed` when the scan cannot read
/// every local file or the sidecar. The view only renders `state` and calls `scan()`, `confirm()`
/// and `cancel()`.
///
/// Settings row rule (`showsSettingsRow`): shown until an import has finished (`importedAt` set in
/// the sidecar, by a run with no failures or by a scan that found nothing left), and after that
/// for as long as items that cannot be imported remain (their list stays readable there).
/// "Check these" titles (`needsCheck`) are shown in the result only and are not persisted.
@MainActor @Observable
public final class ImportModel {
    public private(set) var state: ImportState = .idle
    /// The last progress report of the current or last run.
    public private(set) var lastProgress: (done: Int, total: Int) = (0, 0)
    public private(set) var isRunning = false
    /// The sidecar's `importedAt` is set (read by `refreshStatus`, `scan` and after a run).
    public private(set) var importFinished = false
    /// The plan of the last scan, kept after a run so the result can still list the items that
    /// could not be imported.
    public private(set) var lastPlan: ImportPlan?

    @ObservationIgnored private let store: PlannerStore
    @ObservationIgnored private let sidecar: ItemSidecar
    @ObservationIgnored private let repository: any ItemRepository
    @ObservationIgnored private let destinations: any DefaultDestinations
    @ObservationIgnored private let appleItems: @MainActor () async -> [AgendaItem]
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var runTask: Task<ImportResult, Never>?
    @ObservationIgnored private let afterRun: @MainActor () async -> Void

    /// `appleItems` returns Apple items already loaded (Search's window), for the informational
    /// "look already in Apple" count only. `afterRun` reloads the app's Apple data after a run
    /// that created at least one item (called once the result and the hiding are in place).
    public init(store: PlannerStore, sidecar: ItemSidecar, repository: any ItemRepository,
                destinations: any DefaultDestinations,
                appleItems: @escaping @MainActor () async -> [AgendaItem] = { [] },
                now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .autoupdatingCurrent,
                afterRun: @escaping @MainActor () async -> Void = {}) {
        self.store = store
        self.sidecar = sidecar
        self.repository = repository
        self.destinations = destinations
        self.appleItems = appleItems
        self.now = now
        self.calendar = calendar
        self.afterRun = afterRun
    }

    /// Whether Settings shows the "Import Stark's own items" row.
    public var showsSettingsRow: Bool { !importFinished || hasPendingSteps || !store.notImportedIDs.isEmpty }

    /// A scan would still produce steps: set by the launch check (repeating items and reopened
    /// series copies, the only kinds that can appear after the import finished), by a scan and
    /// after a run. Keeps the row visible after the finish mark so a leftover is never stranded.
    public private(set) var hasPendingSteps = false

    /// Launch (and foreground) work: hides ledgered items, marks the items that cannot be imported
    /// and reads whether the import finished. Cheap: no month loading, no agenda expansion. A
    /// sidecar read failure leaves the row visible (the scan then shows the error).
    public func refreshStatus() async {
        let data: SidecarData
        do { data = try await sidecar.load() } catch {
            importFinished = false
            store.error = "Stark couldn't read its record of imported items; some items may show twice."
            return
        }
        let imported = Set(data.importLedger.keys)
        store.setImportedIDs(imported)
        store.notImportedIDs = ImportPlanner.unrepresentableIDs(events: store.allEvents, reminders: store.allReminders,
                                                               alreadyImported: imported)
        importFinished = data.importedAt != nil
        let candidates = (events: store.allEvents.filter { $0.recurrence != nil },
                          reminders: store.allReminders.filter { $0.recurrence != nil || $0.seriesID != nil })
        hasPendingSteps = candidates.events.contains { !imported.contains($0.id) }
            || candidates.reminders.contains { !imported.contains($0.id) }
            ? !ImportPlanner.plan(events: candidates.events, reminders: candidates.reminders, plans: store.allPlans,
                                  alreadyImported: imported, apple: [], today: now(), calendar: calendar).isEmpty
            : false
    }

    /// Reads every local file and the sidecar, then shows the preview. Any read failure shows the
    /// error instead (never a plan from partial data).
    public func scan() async {
        guard !isRunning else { return }
        if case .scanning = state { return }
        state = .scanning

        // A month that failed earlier is retried by loadAllMonths; only a failure now counts.
        store.error = nil
        await store.loadAllMonths()
        if let error = store.error {
            state = .failed(error)
            return
        }
        guard store.recurringLoaded else {
            state = .failed("Couldn't read recurring items, so nothing can be imported yet.")
            return
        }

        let data: SidecarData
        do { data = try await sidecar.load() } catch {
            state = .failed("Stark's data file could not be read, so nothing can be imported yet: \(error)")
            return
        }
        let imported = Set(data.importLedger.keys)
        store.setImportedIDs(imported)

        let calendars: [AppleCalendarInfo]
        do { calendars = try await repository.writableCalendars() } catch {
            state = .failed("Stark couldn't read your calendars and lists. Try again in a moment.")
            return
        }
        let target = Self.destinations(calendarID: destinations.calendarID, listID: destinations.listID, in: calendars)

        let apple = await appleItems()
        let plan = ImportPlanner.plan(events: store.allEvents, reminders: store.allReminders, plans: store.allPlans,
                                      alreadyImported: imported, apple: apple, today: now(), calendar: calendar)
        store.notImportedIDs = Set(plan.unrepresentable.map(\.localID))
        lastPlan = plan

        var finished = data.importedAt != nil
        if plan.isEmpty && !finished {
            do {
                try await sidecar.markImportFinished(at: now())
                finished = true
            } catch {
                store.error = "Stark could not record that the import finished: \(error)"
            }
        }
        importFinished = finished
        hasPendingSteps = !plan.isEmpty
        state = .preview(plan, target)
    }

    /// Runs the previewed plan. Ignored unless a non-empty preview with valid destinations is
    /// shown and no run is in progress (a second tap never starts a second run).
    public func confirm() async {
        guard !isRunning, case .preview(let plan, let target) = state, !plan.isEmpty, target.problem == nil,
              let calendarID = target.calendar?.id, let listID = target.list?.id else { return }
        isRunning = true
        defer { isRunning = false }
        let total = plan.steps.count
        lastProgress = (0, total)
        state = .running(done: 0, total: total)

        let runner = ImportRunner(repository: repository, sidecar: sidecar, calendarID: calendarID, listID: listID,
                                  now: now)
        let (stream, continuation) = AsyncStream.makeStream(of: (Int, Int).self)
        let consumer = Task { @MainActor [weak self] in
            for await (done, total) in stream {
                guard let self else { continue }
                self.lastProgress = (done, total)
                if case .running = self.state { self.state = .running(done: done, total: total) }
            }
        }
        let task = Task { await runner.run(plan) { done, total in continuation.yield((done, total)) } }
        runTask = task
        let result = await task.value
        runTask = nil
        continuation.finish()
        await consumer.value

        do {
            let data = try await sidecar.load()
            store.setImportedIDs(Set(data.importLedger.keys))
            importFinished = data.importedAt != nil
        } catch {
            store.error = "Stark's data file could not be read after the import: \(error)"
        }
        store.notImportedIDs = Set(plan.unrepresentable.map(\.localID))
        hasPendingSteps = plan.steps.contains { !result.imported.contains($0.localID) }
        state = .finished(result)
        // The runner writes through the repository, not the router, so nothing else reloads the
        // Apple overlay and plan cache (EKEventStoreChanged is not reliable after a write burst,
        // spike f). Also after a partial, cancelled or sidecar-stopped run that created something.
        if !result.imported.isEmpty || result.stoppedBecauseSidecar != nil {
            await afterRun()
        }
    }

    /// During a run: stops after the current item. Otherwise: back to `idle`.
    public func cancel() {
        if isRunning {
            runTask?.cancel()
        } else {
            state = .idle
        }
    }

    /// The default calendar and list looked up among the writable ones; a missing or read-only one
    /// is a problem (the run refuses before starting).
    static func destinations(calendarID: String?, listID: String?, in writable: [AppleCalendarInfo]) -> ImportDestinations {
        let calendar = writable.first { $0.id == calendarID && $0.isWritable && !$0.isReminderList }
        let list = writable.first { $0.id == listID && $0.isWritable && $0.isReminderList }
        return ImportDestinations(calendar: calendar, list: list,
                                  problem: DefaultDestination.problem(calendarID: calendar?.id, listID: list?.id))
    }
}
