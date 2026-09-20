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

    init() {
        let store = Self.makeStore()
        _store = StateObject(wrappedValue: store)
        _pending = StateObject(wrappedValue: PendingCompletions(commit: { id, occurrence in
            Self.commitCompletion(store, id: id, occurrence: occurrence)
        }))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(pending)
        }
    }

    /// What happens when a checkbox's undo window closes (or is flushed): complete the reminder.
    ///
    /// Done and Skip in the detail sheet can resolve the same occurrence while its completion is
    /// still pending, and `completeReminder` is not idempotent for a recurring reminder (each call
    /// adds another exception date and another completed copy). So the commit does nothing if the
    /// reminder is gone (deleted meanwhile) or that occurrence was already resolved another way,
    /// matching the Expo app, whose raw-line-keyed timer finds nothing to complete in either case.
    private static func commitCompletion(_ store: PlannerStore, id: String, occurrence: Date) {
        guard let reminder = store.reminders.first(where: { $0.id == id }), !reminder.isCompleted else { return }
        let calendar = Calendar(identifier: .gregorian)
        if reminder.recurrence != nil,
           reminder.exceptionDates.contains(where: { calendar.isDate($0, inSameDayAs: occurrence) }) {
            return
        }
        store.completeReminder(id: id, on: occurrence)
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
