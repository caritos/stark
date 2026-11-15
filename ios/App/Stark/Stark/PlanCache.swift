// ios/App/Stark/Stark/PlanCache.swift
import Foundation
import Observation
import os
import StarkKit

/// Every plan block of an Apple reminder (kept in Stark's sidecar, a few hundred small records at
/// most), read in one go so the agenda, the planner, the month grid and the year view can read them
/// synchronously. Stark's own plans still come from `PlannerStore.plans`; together each block
/// appears once (`agendaWithApple`, `PlannerPlans`). Refreshed by `ItemRouter.onDidWrite` after
/// every sidecar or Apple write, and when a screen that reads it appears.
///
/// Task 9b: the cache used to hold only the agenda's display range; the planner (any day, its week
/// line, plans elsewhere) and the densities (a whole month or year) need blocks outside it, so it
/// now holds the whole sidecar.
@MainActor @Observable
final class PlanCache {
    private static let log = Logger(subsystem: "com.caritos.todo-txt", category: "PlanCache")

    /// Every Apple plan block, reminderID = model id (`apple-<identifier>`).
    private(set) var applePlans: [PlanBlock] = []
    /// Whether a read has succeeded (the planner waits for it, `PlanCacheState.allowsPlanEdits`).
    private(set) var state = PlanCacheState()
    /// Shows a failed read in the main error banner, once per run of failures (set by `StarkApp`).
    @ObservationIgnored var onLoadFailure: ((String) -> Void)?

    @ObservationIgnored private let router: ItemRouter

    init(router: ItemRouter) {
        self.router = router
    }

    /// The agenda's display range changed: re-read (the cache covers every day, the range is not
    /// needed; kept so the agenda's call site reads as before).
    func show(_ range: ClosedRange<Date>) async {
        await refresh()
    }

    /// Re-reads the sidecar. An unreadable sidecar keeps what was shown, is logged, and shows in
    /// the main error banner once (until a read succeeds again); before any good read the planner
    /// also shows `PlanCacheState.plannerNotice` for as long as it is locked.
    func refresh() async {
        do {
            let plans = try await router.applePlans(in: Date.distantPast...Date.distantFuture)
            // Only a real change redraws the readers.
            if plans != applePlans { applePlans = plans }
            // Only a real change redraws the planner.
            if !state.hasLoaded || state.failure != nil { state.loaded() }
        } catch {
            Self.log.error("Reading Apple plans failed: \(error.localizedDescription, privacy: .public)")
            if let message = state.failed(error.routerMessage) {
                onLoadFailure?(message)
            }
        }
    }
}
