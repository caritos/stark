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
    @EnvironmentObject private var pending: PendingCompletions
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAdd = false
    @State private var selectedItem: AgendaItem?
    @State private var selectedDate = Date()
    @State private var scrollRequest: ScrollRequest?
    /// The date the agenda's display window (`AgendaWindow.range(around:)`) is centred on:
    /// today, until a grid tap outside that window re-centres it.
    @State private var agendaAnchor = Date()

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
                MonthGridView(selectedDate: selectedDate, onSelectDate: selectDate)
                Rectangle()
                    .fill(Colors.separator)
                    .frame(height: 1)
                AgendaView(anchor: agendaAnchor, scrollRequest: scrollRequest, onSelect: { selectedItem = $0 })
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
                } else {
                    // The undo window's timer doesn't survive the app being suspended or
                    // killed, so commit any still-pending completions on the way out.
                    pending.flush()
                }
            }
        }
        .tint(Colors.accent)
        // The design is dark-only (Colors.* are dark-theme tokens); without this, system
        // sheets and Forms would render light with near-white text.
        .preferredColorScheme(.dark)
    }

    /// A day was tapped in the month grid: scroll the agenda to that day's header. A day outside
    /// the agenda's current display window has no section yet, so first re-centre the window on
    /// it, loading the months the new window covers *before* switching, or items in months not
    /// yet read would silently vanish. A day already inside the window never re-centres.
    ///
    /// The re-centre and the scroll request are set in the same transaction, so `AgendaView`
    /// sees the new window and the request together and its (deferred) scroll targets a header
    /// that exists.
    private func selectDate(_ date: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let tapped = calendar.startOfDay(for: date)
        let window = AgendaWindow.range(around: agendaAnchor)
        // Day granularity: the window runs from the start of its first day to the last second
        // of its last, while a tapped day is a noon timestamp, so compare whole days.
        let firstDay = calendar.startOfDay(for: window.lowerBound)
        let lastDay = calendar.startOfDay(for: window.upperBound)
        if tapped < firstDay || tapped > lastDay {
            store.loadMonths(covering: AgendaWindow.range(around: date))
            agendaAnchor = date
        }
        selectedDate = date
        scrollRequest = ScrollRequest(date: date)
    }
}
