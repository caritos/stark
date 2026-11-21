//
//  StarkApp.swift
//  Stark
//
//  Created by Eladio Caritos on 9/17/26.
//

import SwiftUI
import StarkKit
import WidgetKit

@main
struct StarkApp: App {
    @StateObject private var pending: PendingCompletions
    /// The Apple Calendar / Reminders overlay, always on. Access is only ever requested from the
    /// main screen's `AccessRequiredView`, after it explained why, never at launch.
    @State private var overlay: AppleOverlayModel
    /// Where new Apple items go (Settings > Apple Calendar and Reminders).
    @State private var destinations: DefaultDestinationModel
    /// Saved calendar sets (the bottom bar's calendars button); a view over `overlay.selection`.
    @State private var calendarSets: CalendarSetsModel
    @State private var templates = TemplatesModel()
    /// Apple reminders' plan blocks for the agenda (read through the router).
    @State private var planCache: PlanCache
    /// The main screen's notice strip, shared so sheets and the agenda can post to it.
    @State private var notices = NoticeCenter()
    /// The main screen's error banner (Apple write, plan-read and pending-commit failures).
    @State private var errors: ErrorCenter
    /// The optional weather forecast (Settings > Weather). OFF by default: no location prompt and no
    /// network call until the owner turns it on.
    @State private var weather: WeatherModel
    /// Tells the main screen a reminder was just completed (a win moment for the rating prompt).
    @State private var reviewAsk = ReviewAskSignal()
    /// The one EventKit repository, sidecar and router (Apple write path). Every view write goes
    /// through the router.
    private let repository: AppleItemRepository
    private let sidecar: ItemSidecar
    private let router: ItemRouter

    init() {
        // Counts this cold launch toward the rating prompt (never asks here: not at launch).
        ReviewPromptStore().recordLaunch()
        let errors = ErrorCenter()
        _errors = State(initialValue: errors)
        // One EKEventStore for the whole app: the provider creates it lazily and the repository
        // writes through it.
        let provider = EventKitProvider()
        let repository = AppleItemRepository(provider: provider)
        self.repository = repository
        let overlay = AppleOverlayModel(provider: provider)
        _overlay = State(initialValue: overlay)
        let destinations = DefaultDestinationModel(provider: provider, repository: repository,
                                                   keepShown: { [weak overlay] id in
            // Only when hidden: an unchanged assignment would still redraw every overlay reader.
            if overlay?.selection.isShown(id) == false { overlay?.setShown(id, true) }
        })
        _destinations = State(initialValue: destinations)
        _calendarSets = State(initialValue: CalendarSetsModel(overlay: overlay, alwaysShown: { [weak destinations] in
            Set([destinations?.calendarID, destinations?.listID].compactMap { $0 })
        }))
        let sidecar = ItemSidecar(fileURL: Self.sidecarURL(), calendar: .autoupdatingCurrent)
        self.sidecar = sidecar
        let router = ItemRouter(repository: repository, sidecar: sidecar,
                                destinations: destinations, calendar: .autoupdatingCurrent)
        let planCache = PlanCache(router: router)
        planCache.onLoadFailure = { [weak errors] message in errors?.show(message) }
        _planCache = State(initialValue: planCache)
        // EKEventStoreChanged is not reliable after a save (write spike f): reload after every write.
        router.onDidWrite = { [weak overlay, weak planCache] in
            await overlay?.refreshAfterWrite()
            await planCache?.refresh()
            WidgetCenter.shared.reloadAllTimelines()
        }
        self.router = router
        #if targetEnvironment(macCatalyst)
        let settingsAppName = "System Settings"
        #else
        let settingsAppName = "Settings"
        #endif
        _weather = State(initialValue: WeatherModel(location: LocationProvider(),
                                                    calendar: Calendar(identifier: .gregorian),
                                                    settingsAppName: settingsAppName))
        // Through the router to EventKit with the OCCURRENCE's own date (the repository ignores a
        // repeating reminder already past that day, so a double tap never completes the next
        // one); a non-Apple id is refused (`.notApple`). The row stays pending until the write and
        // the overlay reload have landed; a failure shows in the main error banner.
        let reviewAsk = ReviewAskSignal()
        _reviewAsk = State(initialValue: reviewAsk)
        _pending = StateObject(wrappedValue: PendingCompletions(asyncCommit: { id, occurrence in
            do {
                try await router.complete(id: id, on: occurrence)
                // The undo window has passed and the write landed: a win moment.
                ReviewPromptStore().recordCompletion()
                reviewAsk.completionLanded()
            } catch {
                errors.show(error.routerMessage)
            }
        }))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(pending)
                .environment(overlay)
                .environment(destinations)
                .environment(calendarSets)
                .environment(templates)
                .environment(planCache)
                .environment(notices)
                .environment(errors)
                .environment(weather)
                .environment(reviewAsk)
                .environment(\.itemRouter, router)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 480, minHeight: 520)
                #endif
        }
        #if targetEnvironment(macCatalyst)
        .windowResizability(.contentMinSize)
        #endif
    }

    /// `Library/Application Support/Stark/sidecar.json` (plan blocks and outcomes of Apple items,
    /// keyed by EventKit identifier; not in Documents). The directory is created here; a failure
    /// surfaces later as a sidecar write error, never as a crash.
    private static func sidecarURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stark", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("sidecar.json")
    }
}

extension EnvironmentValues {
    /// The app's one `ItemRouter` (set by `StarkApp`); nil only in previews.
    @Entry var itemRouter: ItemRouter? = nil
}
