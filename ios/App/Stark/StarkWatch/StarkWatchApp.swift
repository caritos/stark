//
//  StarkWatchApp.swift
//  StarkWatch
//
//  The Up Next list on the watch. It shows the snapshot the iPhone pushes and reads nothing from
//  EventKit; completing and adding (sent to the iPhone through the outbox) come in later tasks.
//

import StarkKit
import SwiftUI
import WatchConnectivity

@main
struct StarkWatchApp: App {
    @State private var model: WatchAgendaModel
    @State private var addModel: WatchAddModel
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
        _addModel = State(initialValue: WatchAddModel(outbox: outbox, pendingAdds: WatchPendingAdds(outbox: outbox)))
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            WatchListView(model: model, addModel: addModel)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            transport.requestSnapshot()
            model.outbox.expireOld()
        }
        // The phone's updateApplicationContext wakes a suspended watch app with a WatchConnectivity
        // refresh task. Hold it until the session has handed over everything pending, so
        // didReceiveApplicationContext (snapshot save + complication reload) really runs before
        // watchOS suspends the app. The session is already activated in the transport's init path.
        .backgroundTask(.watchConnectivity) {
            for _ in 0..<60 {
                if !WCSession.default.hasContentPending { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
