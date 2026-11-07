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
    private let bridge: ClaudeBridge
    private let secrets: SecretStore

    init() {
        let store = Self.makeStore()
        _store = StateObject(wrappedValue: store)
        // Idempotence (unknown id, already resolved by Done/Skip) lives in `PlannerStore.completeReminder`.
        let secrets = KeychainSecretStore(service: "com.caritos.todo-txt.bridge", account: "pairing")
        self.secrets = secrets
        bridge = ClaudeBridge(store: store, secrets: secrets,
                              replay: BridgeReplayGuard(store: UserDefaultsReplayStore(), now: Date.init))
        _pending = StateObject(wrappedValue: PendingCompletions(commit: { id, occurrence in
            store.completeReminder(id: id, on: occurrence)
        }))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(bridge: bridge, secrets: secrets)
                .environmentObject(store)
                .environmentObject(pending)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 480, minHeight: 520)
                #endif
        }
        #if targetEnvironment(macCatalyst)
        .windowResizability(.contentMinSize)
        #endif
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
