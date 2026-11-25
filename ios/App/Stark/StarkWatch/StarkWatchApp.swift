//
//  StarkWatchApp.swift
//  StarkWatch
//
//  The Up Next list on the watch. It shows the snapshot the iPhone pushes and reads nothing from
//  EventKit; completing and adding (sent to the iPhone through the outbox) come in later tasks.
//

import StarkKit
import SwiftUI

@main
struct StarkWatchApp: App {
    @State private var model: WatchAgendaModel
    private let transport: WCSessionTransport
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let transport = WCSessionTransport()
        let outbox = WatchOutbox(transport: transport, pending: UserDefaultsWatchPendingStore())
        let model = WatchAgendaModel(store: UserDefaultsSnapshotStore(), outbox: outbox)
        transport.start(
            onSnapshot: { snapshot in Task { @MainActor in model.receive(snapshot) } },
            onReply: { reply in Task { @MainActor in outbox.receive(reply) } })
        self.transport = transport
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            WatchListView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            transport.requestSnapshot()
            model.outbox.expireOld()
        }
    }
}
