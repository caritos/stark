//
//  AppleOverlayModel.swift
//  Stark
//
//  Overlay state (always on): access, the device's calendars, which ones are shown and the
//  latest fetched items. Merging, selection and filtering are StarkKit code (tested there); this
//  holds no other logic. EventKit work runs off the main actor through `AppleItemProvider`.
//

import Foundation
import Observation
import os
import StarkKit
import WidgetKit

@MainActor @Observable
final class AppleOverlayModel {
    private enum Key {
        static let excluded = "appleOverlay.excludedCalendarIDs"
    }

    private static let log = Logger(subsystem: "com.caritos.todo-txt", category: "AppleOverlay")

    /// Always on since the Apple write path (phase 1, decision 11): Stark's new items live in
    /// Apple, so they must never vanish from view. The old persisted switch
    /// (`appleOverlay.enabled`) is no longer read, so an install that had it off gets the overlay
    /// on too. Access is still only requested from `AccessRequiredView`'s button.
    var isEnabled: Bool { true }
    var access: AppleAccess
    var calendars: [AppleCalendarInfo] = []
    /// Persisted as the excluded ids only (no names, no paths).
    var selection: AppleSelection {
        didSet {
            defaults.set(Array(selection.excludedIDs).sorted(), forKey: Key.excluded)
            mirrorSelectionForWidget()
            WidgetCenter.shared.reloadAllTimelines()
            applySelection()
        }
    }
    /// The filtered items for the agenda; empty unless enabled and granted.
    private(set) var snapshot = AppleSnapshot(events: [], reminders: [])
    /// Whether the first fetch after launch (or after access was granted) has finished, landed or
    /// failed: until then the agenda shows a loading state instead of empty days.
    private(set) var firstLoad = AgendaFirstLoad()

    @ObservationIgnored private let provider: AppleItemProvider
    @ObservationIgnored private let defaults: UserDefaults
    /// The App Group suite the widget reads (`SelectionMirror`); write only, nil when the suite
    /// cannot be opened. The app itself keeps reading `defaults`.
    @ObservationIgnored private let widgetDefaults: UserDefaults?
    /// The unfiltered result of the last fetch, so a toggle refilters without refetching.
    @ObservationIgnored private var fetched = AppleSnapshot(events: [], reminders: [])
    @ObservationIgnored private var lastRequest: (display: ClosedRange<Date>, today: Date)?
    /// Each screen's display range; reloads fetch their hull.
    @ObservationIgnored private var window = AppleFetchWindow()
    /// Only the newest reload's result is applied, and a superseded `reload` returns only once
    /// the newest one has landed (bounded; see `LatestReloadGate`).
    @ObservationIgnored private let gate = LatestReloadGate()
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    /// Birth years of the shown Birthdays-calendar events, read from Contacts after the snapshot
    /// landed (never on the first-load path) and kept in memory for the model's lifetime.
    @ObservationIgnored private let birthYears: BirthYearCache

    init(provider: AppleItemProvider, defaults: UserDefaults = .standard,
         widgetDefaults: UserDefaults? = UserDefaults(suiteName: SelectionMirror.suiteName),
         birthYearLookup: BirthYearLookup = ContactsBirthYears()) {
        self.provider = provider
        self.defaults = defaults
        self.widgetDefaults = widgetDefaults
        self.birthYears = BirthYearCache(lookup: birthYearLookup)
        selection = AppleSelection(excludedIDs: Set(defaults.stringArray(forKey: Key.excluded) ?? []))
        access = provider.accessState()
        mirrorSelectionForWidget()
        observeStoreChanges()
    }

    /// Copies the excluded ids to the App Group so the widget honours the same calendars.
    private func mirrorSelectionForWidget() {
        guard let widgetDefaults else { return }
        SelectionMirror.write(selection.excludedIDs, to: widgetDefaults)
    }

    deinit {
        changeTask?.cancel()
    }

    /// The only place access is requested: `AccessRequiredView`'s button, after it explained what
    /// access is for (never at launch). Always asks the provider, which requests only the sources
    /// still undetermined, so one left unasked next to a denied one is asked once the user fixes
    /// the other in iOS Settings. The snapshot stays empty until access is granted.
    func enable() async {
        access = await provider.requestAccess()
        if let lastRequest {
            await reload(display: lastRequest.display, today: lastRequest.today)
        } else {
            await refreshCalendars()
        }
    }

    /// The Settings screen appeared or came back to the foreground (the user may have changed
    /// access in iOS Settings): re-read access and, when granted, the calendar list. Never asks.
    /// Access that became granted with the switch on reloads the last range (through the gate,
    /// like the store-changed reload); access that was lost clears the snapshot; no change, no work.
    func refreshAccess() async {
        let previous = access
        access = provider.accessState()
        await refreshCalendars()
        switch AppleAccessChange.action(previous: previous, current: access, isEnabled: isEnabled) {
        case .none:
            break
        case .reload:
            if let lastRequest {
                await reload(display: lastRequest.display, today: lastRequest.today)
            }
        case .clear:
            clearSnapshot()
        }
    }

    /// Drops any in-flight reload's result and empties the snapshot.
    private func clearSnapshot() {
        gate.invalidate()
        emptySnapshots()
    }

    /// Writes only when something is there: an overlay-off user reaches this on every reload, and
    /// an unconditional write to the observed `snapshot` would redraw every screen reading it.
    private func emptySnapshots() {
        let empty = AppleSnapshot(events: [], reminders: [])
        if fetched != empty { fetched = empty }
        if snapshot != empty { snapshot = empty }
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

    /// After Stark itself wrote to Apple (`ItemRouter.onDidWrite`): `EKEventStoreChanged` is not
    /// reliable after a save (write spike f), so the agenda reloads here, for the last "today".
    func refreshAfterWrite() async {
        await refresh(today: lastRequest?.today ?? Date())
    }

    /// The app came to the front: contacts that had no birth year (or no Contacts access) are
    /// asked again on the next snapshot, since either may have changed in the meantime.
    func forgetMissingBirthYears() {
        birthYears.forgetMissing()
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
                self?.markFirstLoadFinished()
            },
            failed: { [weak self] error in
                Self.log.error("Apple overlay fetch failed: \(error.localizedDescription, privacy: .public)")
                self?.markFirstLoadFinished()
            },
            clear: { self.emptySnapshots() }
        )
    }

    // MARK: - Private

    /// Writes only the first time, so later fetches never redraw the screens reading it.
    private func markFirstLoadFinished() {
        guard !firstLoad.hasFinishedOnce else { return }
        firstLoad.fetchFinished()
    }

    private func refreshCalendars() async {
        guard access == .granted else { return }
        let provider = self.provider
        // `calendars()` is a synchronous, nonisolated EventKit read: run it on the concurrent pool.
        let list = await Task.detached { provider.calendars() }.value
        calendars = list
        // The selection is never pruned: `isShown` ignores ids that no longer exist, and a
        // partial list (an account still syncing) must not delete the user's hidden calendars.
    }

    private func applySelection() {
        guard isEnabled, access == .granted else {
            let empty = AppleSnapshot(events: [], reminders: [])
            if snapshot != empty { snapshot = empty }
            return
        }
        let filtered = selection.filtered(fetched)
        // Only birthdays of calendars the owner shows; hidden ones never reach Contacts.
        let ids = BirthYear.contactIDsNeeded(in: filtered.events)
        let next = AppleSnapshot(events: filtered.events, reminders: filtered.reminders,
                                 birthYears: birthYears.years(for: ids))
        if snapshot != next { snapshot = next }
        guard !birthYears.missing(from: ids).isEmpty else { return }
        // The snapshot is already published (cake, no age yet); the lookup (and the one Contacts
        // prompt) runs off the main actor, one at a time. When it learned a year, the snapshot is
        // re-derived from whatever is current then, so an older fetch is never republished.
        Task { [weak self] in
            guard let self, await self.birthYears.load(ids) else { return }
            self.applySelection()
        }
    }

    private func observeStoreChanges() {
        guard let name = provider.storeChangedNotification else { return }
        changeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: name) {
                // Calendar or Reminders changed (in Stark or elsewhere): refresh the Home Screen widget.
                WidgetCenter.shared.reloadAllTimelines()
                guard let self else { return }
                guard let request = self.lastRequest else { continue }
                await self.reload(display: request.display, today: request.today)
            }
        }
    }
}
