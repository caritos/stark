//
//  AppleOverlayModel.swift
//  Stark
//
//  Read-only overlay state: on/off, access, the device's calendars, which ones are shown and the
//  latest fetched items. Merging, selection and filtering are StarkKit code (tested there); this
//  holds no other logic. EventKit work runs off the main actor through `AppleItemProvider`.
//

import Foundation
import Observation
import os
import StarkKit

@MainActor @Observable
final class AppleOverlayModel {
    private enum Key {
        static let enabled = "appleOverlay.enabled"
        static let excluded = "appleOverlay.excludedCalendarIDs"
    }

    private static let log = Logger(subsystem: "com.caritos.todo-txt", category: "AppleOverlay")

    /// Off by default. Persisted.
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.enabled) }
    }
    var access: AppleAccess
    var calendars: [AppleCalendarInfo] = []
    /// Persisted as the excluded ids only (no names, no paths).
    var selection: AppleSelection {
        didSet {
            defaults.set(Array(selection.excludedIDs).sorted(), forKey: Key.excluded)
            applySelection()
        }
    }
    /// The filtered items for the agenda; empty unless enabled and granted.
    private(set) var snapshot = AppleSnapshot(events: [], reminders: [])

    @ObservationIgnored private let provider: AppleItemProvider
    @ObservationIgnored private let defaults: UserDefaults
    /// The unfiltered result of the last fetch, so a toggle refilters without refetching.
    @ObservationIgnored private var fetched = AppleSnapshot(events: [], reminders: [])
    @ObservationIgnored private var lastRequest: (display: ClosedRange<Date>, today: Date)?
    /// Bumped on every reload/disable so a slow, older fetch cannot overwrite a newer result.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var changeTask: Task<Void, Never>?

    init(provider: AppleItemProvider, defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.enabled)
        selection = AppleSelection(excludedIDs: Set(defaults.stringArray(forKey: Key.excluded) ?? []))
        access = provider.accessState()
        observeStoreChanges()
    }

    deinit {
        changeTask?.cancel()
    }

    /// Turning the overlay on is the only place access is requested (never at launch). The
    /// switch stays on even if access is refused, so Settings can show the denied state; the
    /// snapshot stays empty until access is granted.
    func enable() async {
        isEnabled = true
        if provider.accessState() == .notAsked {
            access = await provider.requestAccess()
        } else {
            access = provider.accessState()
        }
        if let lastRequest {
            await reload(display: lastRequest.display, today: lastRequest.today)
        } else {
            await refreshCalendars()
        }
    }

    func disable() {
        isEnabled = false
        generation += 1
        fetched = AppleSnapshot(events: [], reminders: [])
        snapshot = fetched
    }

    func setShown(_ id: String, _ shown: Bool) {
        var next = selection
        if shown { next.excludedIDs.remove(id) } else { next.excludedIDs.insert(id) }
        selection = next
    }

    /// Fetches events over `display` and reminders over `display` plus the overdue lookback. The
    /// previous snapshot stays until the new one lands; a failed fetch keeps it.
    func reload(display: ClosedRange<Date>, today: Date) async {
        lastRequest = (display, today)
        access = provider.accessState()
        guard isEnabled, access == .granted else {
            generation += 1
            fetched = AppleSnapshot(events: [], reminders: [])
            snapshot = fetched
            return
        }
        generation += 1
        let mine = generation
        let reminderStart = Calendar.autoupdatingCurrent.date(
            byAdding: .day, value: -AgendaWindow.overdueLookbackDays, to: display.lowerBound) ?? display.lowerBound
        let reminderRange = reminderStart...display.upperBound
        let provider = self.provider
        await refreshCalendars()
        do {
            // `fetch` is `@concurrent` (protocol and witness): it leaves the main actor here.
            let result = try await provider.fetch(events: display, reminders: reminderRange)
            guard mine == generation else { return }
            fetched = result
            applySelection()
        } catch {
            Self.log.error("Apple overlay fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private func refreshCalendars() async {
        guard access == .granted else { return }
        let provider = self.provider
        // `calendars()` is a synchronous, nonisolated EventKit read: run it on the concurrent pool.
        let list = await Task.detached { provider.calendars() }.value
        calendars = list
        // Prune only with access granted and a real list, or every calendar would turn back on.
        guard !list.isEmpty else { return }
        let pruned = selection.pruned(toExisting: Set(list.map(\.id)))
        if pruned != selection { selection = pruned }
    }

    private func applySelection() {
        guard isEnabled, access == .granted else {
            snapshot = AppleSnapshot(events: [], reminders: [])
            return
        }
        snapshot = selection.filtered(fetched)
    }

    private func observeStoreChanges() {
        guard let name = provider.storeChangedNotification else { return }
        changeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: name) {
                guard let self else { return }
                guard let request = self.lastRequest else { continue }
                await self.reload(display: request.display, today: request.today)
            }
        }
    }
}
