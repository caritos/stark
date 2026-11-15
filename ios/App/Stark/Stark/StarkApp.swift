//
//  StarkApp.swift
//  Stark
//
//  Created by Eladio Caritos on 9/17/26.
//

import SwiftUI
import StarkKit

@main
struct StarkApp: App {
    @StateObject private var store: PlannerStore
    @StateObject private var pending: PendingCompletions
    /// The Apple Calendar / Reminders overlay, always on. Access is only ever requested from the
    /// main screen's `AccessRequiredView`, after it explained why, never at launch.
    @State private var overlay: AppleOverlayModel
    /// Where new Apple items go (Settings > Apple Calendar and Reminders).
    @State private var destinations: DefaultDestinationModel
    /// Apple reminders' plan blocks for the agenda (read through the router).
    @State private var planCache: PlanCache
    /// The main screen's notice strip, shared so sheets and the agenda can post to it.
    @State private var notices = NoticeCenter()
    /// The one EventKit repository, sidecar and router (Apple write path). Every view write goes
    /// through the router; the Claude Code bridge writes through the same repository and sidecar.
    private let repository: AppleItemRepository
    private let sidecar: ItemSidecar
    private let router: ItemRouter
    private let bridge: ClaudeBridge
    private let secrets: SecretStore

    init() {
        let store = Self.makeStore()
        _store = StateObject(wrappedValue: store)
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
        let sidecar = ItemSidecar(fileURL: Self.sidecarURL(), calendar: .autoupdatingCurrent)
        self.sidecar = sidecar
        let router = ItemRouter(repository: repository, local: store, sidecar: sidecar,
                                destinations: destinations, calendar: .autoupdatingCurrent)
        let planCache = PlanCache(router: router)
        planCache.onLoadFailure = { [weak store] message in store?.error = message }
        _planCache = State(initialValue: planCache)
        // EKEventStoreChanged is not reliable after a save (write spike f): reload after every write.
        router.onDidWrite = { [weak overlay, weak planCache] in
            await overlay?.refreshAfterWrite()
            await planCache?.refresh()
        }
        self.router = router
        let secrets = KeychainSecretStore(service: "com.caritos.todo-txt.bridge", account: "pairing")
        self.secrets = secrets
        // Bridge items go to Apple (default calendar / list) and are ledgered in the sidecar.
        bridge = ClaudeBridge(repository: repository, sidecar: sidecar, destinations: destinations,
                              hasAccess: { provider.accessState() == .granted }, secrets: secrets,
                              replay: BridgeReplayGuard(store: UserDefaultsReplayStore(), now: Date.init),
                              calendar: .autoupdatingCurrent)
        // Through the router: Stark's ids to the local store (idempotence, e.g. already resolved by
        // Done/Skip, lives in `PlannerStore.completeReminder`), Apple ids to EventKit with the
        // OCCURRENCE's own date (the repository ignores a repeating reminder already past that
        // day, so a double tap never completes the next one). The row stays pending until the
        // write and the overlay reload have landed; a failure shows in the main error banner.
        _pending = StateObject(wrappedValue: PendingCompletions(asyncCommit: { id, occurrence in
            do {
                try await router.complete(id: id, on: occurrence)
            } catch {
                store.error = error.routerMessage
            }
        }))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(bridge: bridge, secrets: secrets)
                .environmentObject(store)
                .environmentObject(pending)
                .environment(overlay)
                .environment(destinations)
                .environment(planCache)
                .environment(notices)
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

    private static func makeStore() -> PlannerStore {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = PlannerFile(
            directory: documents,
            pendingDirectory: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PendingWrites")
        )
        return PlannerStore(file: file)
    }
}

extension EnvironmentValues {
    /// The app's one `ItemRouter` (set by `StarkApp`); nil only in previews.
    @Entry var itemRouter: ItemRouter? = nil
}
