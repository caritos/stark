// ios/App/Stark/Stark/AgendaView.swift
import SwiftUI
import StarkKit

struct AgendaView: View {
    @EnvironmentObject private var store: PlannerStore
    let onSelect: (AgendaItem) -> Void

    var body: some View {
        let now = Date()
        let items = buildAgendaItems(
            events: store.events,
            reminders: store.reminders,
            in: AgendaWindow.range(around: now),
            today: now
        )

        List(items) { item in
            Button {
                onSelect(item)
            } label: {
                AgendaRowView(item: item)
            }
            .listRowBackground(Colors.background)
        }
        .scrollContentBackground(.hidden)
        .background(Colors.background)
        .navigationTitle("Agenda")
    }
}
