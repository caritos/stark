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
    @State private var showAdd = false
    @State private var selectedItem: AgendaItem?

    var body: some View {
        NavigationStack {
            AgendaView(onSelect: { selectedItem = $0 })
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add", systemImage: "plus") { showAdd = true }
                    }
                }
                .sheet(isPresented: $showAdd) { AddItemView() }
                .sheet(item: $selectedItem) { item in EditItemView(item: item) }
                .task { store.start(around: Date()) }
        }
    }
}
