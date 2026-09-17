// ios/App/Stark/Stark/AgendaView.swift
import SwiftUI
import StarkKit

struct AgendaView: View {
    @EnvironmentObject private var store: PlannerStore
    let onSelect: (AgendaItem) -> Void

    var body: some View {
        let rangeStart = DateMath.date(from: DateMath.addDays(DateMath.isoDate(from: Date()), -14))
        let rangeEnd = DateMath.date(from: DateMath.addDays(DateMath.isoDate(from: Date()), 60))
        let items = buildAgendaItems(events: store.events, reminders: store.reminders, in: rangeStart...rangeEnd)

        List(items) { item in
            Button {
                onSelect(item)
            } label: {
                HStack {
                    Text(item.title)
                        .foregroundStyle(Colors.text)
                    Spacer()
                    Text(item.occurrence.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(Colors.textSecondary)
                }
            }
            .listRowBackground(Colors.background)
        }
        .scrollContentBackground(.hidden)
        .background(Colors.background)
        .navigationTitle("Agenda")
    }
}
