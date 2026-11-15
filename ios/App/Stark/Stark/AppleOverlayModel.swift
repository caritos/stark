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
    /// Each screen's display range; reloads fetch their hull.
    @ObservationIgnored private var window = AppleFetchWindow()
    /// Only the newest reload's result is applied, and a superseded `reload` returns only once
    /// the newest one has landed (bounded; see `LatestReloadGate`).
    @ObservationIgnored private let gate = LatestReloadGate()
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

    /// Turning the overlay on is the only place access is requested (never at launch). Always
    /// asks the provider, which requests only the sources still undetermined, so one left unasked
    /// next to a denied one is asked once the user fixes the other in iOS Settings. The switch
    /// stays on even if access is refused, so Settings can show the denied state; the snapshot
    /// stays empty until access is granted.
    func enable() async {
        isEnabled = true
        access = await provider.requestAccess()
        if let lastRequest {
            await reload(display: lastRequest.display, today: lastRequest.today)
        } else {
            await refreshCalendars()
        }
    }

    /// The Settings screen appeared or came back to the foreground (the user may have changed
    /// access in iOS Settings): re-read access and, when granted, the calendar list. Never asks.
    func refreshAccess() async {
        access = provider.accessState()
        await refreshCalendars()
    }

    func disable() {
        isEnabled = false
        gate.invalidate()
        fetched = AppleSnapshot(events: [], reminders: [])
        snapshot = fetched
    }

    func setShown(_ id: String, _ shown: Bool) {
        var next = selection
        if shown { next.excludedIDs.remove(id) } else { next.excludedIDs.insert(id) }
        selection = next
    }

    /// Whether a reload can change the snapshot. When false the snapshot is empty and stays empty,
    /// so a caller that moves the window need not wait for a reload.
    var isActive: Bool { isEnabled && provider.accessState() == .granted }

    /// A screen's range changed: fetch over the hull of every screen's range (`AppleFetchWindow`),
    /// so the month grid's reload cannot drop the agenda's items. `nil` releases the screen.
    func reload(for screen: AppleFetchWindow.Screen, display: ClosedRange<Date>?, today: Date) async {
        window.set(screen, display)
        await refresh(today: today)
    }

    /// Re-fetches the current hull (foreground). Does nothing before any screen asked for data.
    func refresh(today: Date) async {
        guard let covering = window.covering else { return }
        await reload(display: covering, today: today)
    }

    /// Fetches events over `display` and reminders over `display` plus the overdue lookback. The
    /// previous snapshot stays until the new one lands; a failed fetch keeps it. Returns once the
    /// newest reload in flight has landed (or failed), not just this one's fetch, so a caller that
    /// moves the window afterwards never shows it before its data (`LatestReloadGate`).
    func reload(display: ClosedRange<Date>, today: Date) async {
        lastRequest = (display, today)
        access = provider.accessState()
        let reminderStart = Calendar.autoupdatingCurrent.date(
            byAdding: .day, value: -AgendaWindow.overdueLookbackDays, to: display.lowerBound) ?? display.lowerBound
        let reminderRange = reminderStart...display.upperBound
        let provider = self.provider
        await gate.run(
            active: isEnabled && access == .granted,
            fetch: { [weak self] in
                await self?.refreshCalendars()
                // `fetch` is `@concurrent` (protocol and witness): it leaves the main actor here.
                return try await provider.fetch(events: display, reminders: reminderRange)
            },
            apply: { [weak self] result in
                self?.fetched = result
                self?.applySelection()
            },
            failed: { error in
                Self.log.error("Apple overlay fetch failed: \(error.localizedDescription, privacy: .public)")
            },
            clear: {
                fetched = AppleSnapshot(events: [], reminders: [])
                snapshot = fetched
            }
        )
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
