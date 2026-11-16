// ios/App/Stark/Stark/SearchView.swift
import SwiftUI
import Combine
import StarkKit

/// Full-history text search over titles, notes, and locations. Unlike the agenda, which only
/// ever shows what's currently loaded (today's display window, plus whatever's been scrolled
/// or tapped into), this screen loads every month file that exists on disk the first time it
/// appears (`PlannerStore.loadAllMonths()`), so a search can find any of Stark's own items ever saved. Apple items
/// are covered only within the window below, an Apple event series as one row. While it is
/// open it also registers a two-years-either-side range with the Apple overlay's fetch window
/// (`SearchWindow`, decision 10). A tapped result opens through `AgendaItemDetailSheet`, so an
/// Apple item in a writable calendar or list opens its editor.
///
/// One unconditional match across every relevant field, no filter/field picker -- considered
/// during design (a Fantastical-style Title/Notes/Location/All row) and dropped for
/// simplicity.
struct SearchView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(AppleOverlayModel.self) private var overlay
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isLoadingHistory = true
    @State private var selectedItem: AgendaItem?
    /// The results, recomputed only when the query, the Apple snapshot or the store's items change
    /// (not on every body pass: with a four-year Apple window that is thousands of items).
    @State private var results: [AgendaItem] = []
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
                                    // "No date" for an undated Apple reminder (never its sentinel).
                                    Text(item.isUndatedApple ? AgendaItem.noDateText : AgendaFormat.shortDate(item.displayDate))
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
                SquareToolbarButton(systemImage: "xmark", label: "Close", placement: .cancellationAction) { dismiss() }
            }
            .task {
                // Apple events two years either side of today while Search is open (decision 10);
                // the shared fetch window keeps the agenda's own range too.
                let now = Date()
                async let apple: Void = overlay.reload(for: .search, display: SearchWindow.range(around: now), today: now)
                await store.loadAllMonths()
                await apple
                isLoadingHistory = false
            }
            // Released on close so the overlay goes back to the agenda's window.
            .onDisappear {
                Task { await overlay.reload(for: .search, display: nil, today: Date()) }
            }
            .sheet(item: $selectedItem) { item in AgendaItemDetailSheet(item: item) }
            .onChange(of: query) { refreshResults() }
            .onChange(of: overlay.snapshot) { refreshResults() }
            // `$events`/`$reminders` publish before the store changes, so use the published values.
            .onReceive(store.$events.combineLatest(store.$reminders)) { events, reminders in
                refreshResults(events: events, reminders: reminders)
            }
        }
        .tint(Colors.accent)
    }

    private func refreshResults(events: [Event]? = nil, reminders: [Reminder]? = nil) {
        results = SearchResults.find(events: events ?? store.events, reminders: reminders ?? store.reminders,
                                     apple: overlay.snapshot, query: query)
    }
}
