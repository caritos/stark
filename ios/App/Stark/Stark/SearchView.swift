// ios/App/Stark/Stark/SearchView.swift
import SwiftUI
import StarkKit

/// Full-history text search over titles, notes, and locations. Unlike the agenda, which only
/// ever shows what's currently loaded (today's display window, plus whatever's been scrolled
/// or tapped into), this screen loads every month file that exists on disk the first time it
/// appears (`PlannerStore.loadAllMonths()`), so a search can find anything ever saved.
///
/// One unconditional match across every relevant field, no filter/field picker -- considered
/// during design (a Fantastical-style Title/Notes/Location/All row) and dropped for
/// simplicity.
struct SearchView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isLoadingHistory = true
    @State private var selectedItem: AgendaItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search", text: $query)
                    .foregroundStyle(Colors.text)
                    .padding(Spacing.sm)
                    .background(Colors.separator)
                    .padding(Spacing.md)

                if isLoadingHistory {
                    Spacer()
                    ProgressView()
                        .tint(Colors.accent)
                    Spacer()
                } else if query.isEmpty {
                    Spacer()
                } else {
                    List {
                        ForEach(results) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                AgendaRowView(item: item)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparatorTint(Colors.separator)
                            .listRowBackground(Colors.background)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Colors.background)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                FlatToolbarButton(title: "Close", placement: .cancellationAction) { dismiss() }
            }
            .task {
                await store.loadAllMonths()
                isLoadingHistory = false
            }
            .sheet(item: $selectedItem) { item in EditItemView(item: item) }
        }
        .tint(Colors.accent)
        .preferredColorScheme(.dark)
    }

    /// Every event/reminder matching `query`, sorted by date. Built directly from
    /// `store.events`/`store.reminders` (not through occurrence expansion, unlike the agenda)
    /// -- a search result represents the item's own master record, one row per stored
    /// event/reminder, not per calendar occurrence.
    private var results: [AgendaItem] {
        guard !query.isEmpty else { return [] }
        let needle = query.lowercased()
        var found: [AgendaItem] = []
        for event in store.events where matches(event, needle: needle) {
            found.append(AgendaItem(kind: .event(event), occurrence: event.start, displayDate: event.start, isOverdue: false))
        }
        for reminder in store.reminders where matches(reminder, needle: needle) {
            let date = reminder.dueDate ?? Date()
            found.append(AgendaItem(kind: .reminder(reminder), occurrence: date, displayDate: date, isOverdue: false))
        }
        return found.sorted { $0.displayDate < $1.displayDate }
    }

    private func matches(_ event: Event, needle: String) -> Bool {
        event.title.lowercased().contains(needle)
            || (event.notes?.lowercased().contains(needle) ?? false)
            || (event.location?.lowercased().contains(needle) ?? false)
    }

    private func matches(_ reminder: Reminder, needle: String) -> Bool {
        reminder.title.lowercased().contains(needle)
            || (reminder.notes?.lowercased().contains(needle) ?? false)
    }
}
