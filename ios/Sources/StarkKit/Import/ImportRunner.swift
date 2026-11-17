// ios/Sources/StarkKit/Import/ImportRunner.swift
import Foundation

/// What one `ImportRunner.run` did.
public struct ImportResult: Sendable {
    /// Local ids created in Apple and ledgered, in order.
    public var imported: [String] = []
    /// Steps that could not be created (they are not ledgered; a later run retries them).
    public var failed: [(title: String, message: String)] = []
    /// Titles of repeating events whose removed occurrences could not all be deleted in Apple.
    /// The series itself is created and ledgered; the owner should check it in Calendar.
    public var needsCheck: [String] = []
    /// Set when the sidecar could not be written: the run stopped at once. The message names the
    /// item that was created in Apple but could not be ledgered (if any).
    public var stoppedBecauseSidecar: String?
    public var cancelled = false
    /// Set when the sidecar write failed AND the just-created item could not be deleted again, so
    /// it exists in Apple unrecorded and a rerun may add it a second time.
    public var rollbackFailed = false

    /// Whether the screen may offer "Try Again": only when a rerun cannot duplicate an item, i.e.
    /// something is left to retry (failed steps, a cancelled run, a sidecar stop) and no stop left
    /// an unrecorded item behind.
    public var canRetry: Bool {
        guard !rollbackFailed else { return false }
        return !failed.isEmpty || cancelled || stoppedBecauseSidecar != nil
    }

    public init() {}
}

/// Runs an `ImportPlan` against Apple, one item at a time. Each item is created, then ledgered in
/// ONE sidecar write, before the next starts, so a rerun adds only what is missing. A kill between
/// the EventKit commit and the ledger write can leave at most that one item in Apple unrecorded (a
/// rerun may then add it a second time; the preview's probable-duplicate count shows it). A failed
/// ledger write is rolled back by deleting the item again. It never reads or writes the `.ics` files.
public actor ImportRunner {
    private let repository: ItemRepository
    private let sidecar: ItemSidecar
    private let calendarID: String
    private let listID: String
    private let now: @Sendable () -> Date

    public init(repository: ItemRepository, sidecar: ItemSidecar, calendarID: String, listID: String,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.sidecar = sidecar
        self.calendarID = calendarID
        self.listID = listID
        self.now = now
    }

    /// `progress(done, total)` is called after each step that was attempted (`done` counts attempted
    /// steps of this plan, skipped already-imported ones included).
    public func run(_ plan: ImportPlan, progress: @Sendable (Int, Int) -> Void) async -> ImportResult {
        var result = ImportResult()
        let total = plan.steps.count

        if let problem = DefaultDestination.problem(calendarID: calendarID.isEmpty ? nil : calendarID,
                                                    listID: listID.isEmpty ? nil : listID) {
            result.failed = plan.steps.map { (title: $0.title, message: problem) }
            return result
        }

        let already: Set<String>
        do {
            already = try await sidecar.importedIDs()
        } catch {
            result.stoppedBecauseSidecar = "Stark's data file could not be read, so nothing was imported: \(error)"
            return result
        }

        var done = 0
        for step in plan.steps {
            if Task.isCancelled { result.cancelled = true; return result }
            done += 1
            if already.contains(step.localID) { progress(done, total); continue }

            let ref: AppleItemRef
            do {
                switch step.kind {
                case .event:
                    guard let event = step.event else { throw ImportRunnerError.missingPayload }
                    ref = try await repository.addEvent(event, calendarID: calendarID)
                case .reminder:
                    guard let reminder = step.reminder else { throw ImportRunnerError.missingPayload }
                    ref = try await repository.addReminder(reminder, listID: listID)
                }
            } catch {
                result.failed.append((title: step.title, message: Self.message(error)))
                progress(done, total)
                continue
            }

            do {
                try await sidecar.recordImport(ImportRecord(
                    localID: step.localID, identifier: ref.identifier, externalID: ref.externalID,
                    plans: step.plans, outcomes: step.outcomes))
            } catch {
                // The item exists in Apple but is not ledgered: delete it again so a rerun is clean.
                let reason = Self.message(error)
                do {
                    try await repository.delete(ref)
                    result.stoppedBecauseSidecar = "\"\(step.title)\" could not be recorded (\(reason)), so it was "
                        + "removed from Apple again. Stopped; nothing was added twice."
                } catch {
                    result.rollbackFailed = true
                    result.stoppedBecauseSidecar = "\"\(step.title)\" was created in Apple but Stark could not record "
                        + "it (\(reason)) or remove it again. Stopped; check Apple, and running the import again "
                        + "may add it twice."
                }
                return result
            }
            result.imported.append(step.localID)

            for date in step.exceptionDates {
                do { try await repository.deleteOccurrence(ref, on: date) } catch {
                    if !result.needsCheck.contains(step.title) { result.needsCheck.append(step.title) }
                }
            }
            progress(done, total)
        }

        if result.failed.isEmpty, !plan.steps.isEmpty {
            do { try await sidecar.markImportFinished(at: now()) } catch {
                result.stoppedBecauseSidecar = "Every item was imported, but Stark could not record that it finished "
                    + "(\(Self.message(error)))."
            }
        }
        return result
    }

    private static func message(_ error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription { return d }
        return String(describing: error)
    }
}

private enum ImportRunnerError: Error { case missingPayload }
