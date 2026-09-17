//
//  ContentView.swift
//  Stark
//
//  Created by Eladio Caritos on 9/17/26.
//

import SwiftUI
import StarkKit

struct ContentView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAdd = false
    @State private var selectedItem: AgendaItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = store.error {
                    Button {
                        store.error = nil
                    } label: {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Colors.text)
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Colors.accent)
                    }
                }
                AgendaView(onSelect: { selectedItem = $0 })
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { showAdd = true }
                }
            }
            .sheet(isPresented: $showAdd) { AddItemView() }
            .sheet(item: $selectedItem) { item in EditItemView(item: item) }
            .task {
                let range = AgendaWindow.range(around: Date())
                store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    store.retryPendingWrites()
                }
            }
        }
    }
}
