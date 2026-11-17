// ios/App/Stark/Stark/SearchView.swift
import SwiftUI
import StarkKit

/// Text search over titles, notes, and locations of Apple items: every open reminder, and events
/// and completed reminders within the window below, an Apple event series as one row. While it
/// is open it registers a two-years-either-side range with the Apple overlay's fetch window
/// (`SearchWindow`, decision 10; phase 3 decision 4 keeps this scope). A tapped result opens through `AgendaItemDetailSheet`, so an
/// Apple item in a writable calendar or list opens its editor.
///
/// One unconditional match across every relevant field, no filter/field picker -- considered
/// during design (a Fantastical-style Title/Notes/Location/All row) and dropped for
/// simplicity.
struct SearchView: View {
    @Environment(AppleOverlayModel.self) private var overlay
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isLoadingHistory = true
    @State private var selectedItem: AgendaItem?
    /// The results, recomputed only when the query or the Apple snapshot changes
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
                    .background(Colors.card, in: RoundedRectangle(cornerRadius: 10))
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
                await overlay.reload(for: .search, display: SearchWindow.range(around: now), today: now)
                isLoadingHistory = false
                refreshResults()
            }
            // Released on close so the overlay goes back to the agenda's window.
            .onDisappear {
                Task { await overlay.reload(for: .search, display: nil, today: Date()) }
            }
            .sheet(item: $selectedItem) { item in AgendaItemDetailSheet(item: item) }
            .onChange(of: query) { refreshResults() }
            .onChange(of: overlay.snapshot) { refreshResults() }
        }
        .tint(Colors.accent)
    }

    private func refreshResults() {
        results = SearchResults.find(events: [], reminders: [], apple: overlay.snapshot, query: query)
    }
}
