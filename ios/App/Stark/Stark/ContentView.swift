//
//  ContentView.swift
//  Stark
//
//  Created by Eladio Caritos on 9/17/26.
//

import SwiftUI
import StarkKit

/// One screen: month grid on top, day-grouped agenda filling the rest.
struct ContentView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAdd = false
    @State private var selectedItem: AgendaItem?
    @State private var selectedDate = Date()
    @State private var scrollRequest: ScrollRequest?

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
                MonthGridView(selectedDate: selectedDate) { date in
                    selectedDate = date
                    scrollRequest = ScrollRequest(date: date)
                }
                Rectangle()
                    .fill(Colors.separator)
                    .frame(height: 1)
                AgendaView(scrollRequest: scrollRequest, onSelect: { selectedItem = $0 })
            }
            .background(Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                FlatToolbarButton(title: "Add", systemImage: "plus", placement: .primaryAction) { showAdd = true }
            }
            .sheet(isPresented: $showAdd) { AddItemView() }
            .sheet(item: $selectedItem) { item in EditItemView(item: item) }
            .task {
                // Load the wider window (includes the overdue lookback), not the display window.
                let range = AgendaWindow.loadRange(around: Date())
                store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    store.retryPendingWrites()
                }
            }
        }
        .tint(Colors.accent)
        // The design is dark-only (Colors.* are dark-theme tokens); without this, system
        // sheets and Forms would render light with near-white text.
        .preferredColorScheme(.dark)
    }
}
