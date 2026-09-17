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
    @StateObject private var store = makeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
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
