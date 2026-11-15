// ios/App/Stark/Stark/PlanCache.swift
import Foundation
import Observation
import os
import StarkKit

/// Plan blocks of Apple reminders (kept in Stark's sidecar) for the agenda's display range, read
/// once per window move or write so the agenda can read them synchronously while it builds its
/// rows. Stark's own plans still come from `PlannerStore.plans`; together each block appears once
/// (`agendaWithApple`). Refreshed by `ItemRouter.onDidWrite` after every sidecar or Apple write.
@MainActor @Observable
final class PlanCache {
    private static let log = Logger(subsystem: "com.caritos.todo-txt", category: "PlanCache")

    private(set) var applePlans: [PlanBlock] = []

    @ObservationIgnored private let router: ItemRouter
    @ObservationIgnored private var range: ClosedRange<Date>?

    init(router: ItemRouter) {
        self.router = router
    }

    /// The agenda's display range changed.
    func show(_ range: ClosedRange<Date>) async {
        self.range = range
        await refresh()
    }

    /// Re-reads the current range. An unreadable sidecar keeps what was shown (logged): planner
    /// saves report that error themselves.
    func refresh() async {
        guard let range else { return }
        do {
            let plans = try await router.applePlans(in: range)
            // Only a real change redraws the agenda.
            if plans != applePlans { applePlans = plans }
        } catch {
            Self.log.error("Reading Apple plans failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
