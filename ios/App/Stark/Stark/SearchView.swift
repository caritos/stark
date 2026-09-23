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
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search", text: $query)
                    .focused($searchFocused)
                    .foregroundStyle(Colors.text)
                    .padding(Spacing.sm)
                    .background(Colors.separator)
                    .padding(Spacing.md)
                // Trimmed (unlike Add/Edit's fields): a trailing space would make the search
                // require a literal space right after the tag in the matched text, which fails
                // whenever the tag is the last word of a title/notes/location.
                TagSuggestionRow(text: query) {
                    query = TagAutocomplete.applying($0, to: query).trimmingCharacters(in: .whitespaces)
                }
                .padding(.horizontal, Spacing.md)

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
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(AgendaFormat.shortDate(item.displayDate))
                                        .font(Fonts.mono(11))
                                        .foregroundStyle(Colors.textSecondary)
                                    AgendaRowView(item: item)
                                }
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
            .sigilKeyboardBar(isVisible: searchFocused) { query = TagAutocomplete.appending($0, to: query) }
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

    private var results: [AgendaItem] {
        SearchResults.find(events: store.events, reminders: store.reminders, query: query)
    }
}
