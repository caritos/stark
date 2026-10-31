// ios/App/Stark/Stark/WeeklyReviewView.swift
import SwiftUI
import StarkKit

/// One Sunday-Saturday week: what was done and what is still open. All the bucketing lives in
/// `WeeklyReview` (StarkKit); this view only loads the months a week needs, pages between weeks
/// and lays the result out. Opens on last week on a Monday, the current week otherwise.
struct WeeklyReviewView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var weekStart: Date
    @State private var selectedItem: AgendaItem?
    private let today: Date

    init(today: Date = Date()) {
        self.today = today
        _weekStart = State(initialValue: WeeklyReview.defaultWeekStart(today: today))
    }

    private var review: WeeklyReview {
        WeeklyReview.summary(events: store.events, reminders: store.reminders, weekStarting: weekStart, today: today)
    }

    var body: some View {
        NavigationStack {
            let review = review
            List {
                Section {
                    header(review)
                        .listRowBackground(Colors.background)
                        .listRowSeparator(.hidden)
                }
                section("Completed", items: review.completed, empty: "Nothing completed this week.")
                section("Still open", items: review.open, empty: "Nothing left open.")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Colors.background)
            .navigationTitle("Weekly Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SquareToolbarButton(systemImage: "xmark", label: "Close", placement: .cancellationAction) { dismiss() }
                // Plain text of the week (issue #111), for pasting into a note or another tool.
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: review.shareText()) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Colors.text)
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Share weekly review")
                }
            }
            .sheet(item: $selectedItem) { item in EditItemView(item: item) }
        }
        .tint(Colors.accent)
        .preferredColorScheme(.dark)
        // Load before showing: items in month files that aren't in memory silently vanish.
        .task(id: weekStart) { loadWeek() }
    }

    private func loadWeek() {
        store.loadMonths(covering: WeeklyReview.loadRange(forWeekStarting: weekStart, today: today))
    }

    private func header(_ review: WeeklyReview) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                pagingButton("chevron.left", label: "Previous week") {
                    weekStart = WeeklyReview.weekStart(before: weekStart)
                }
                Spacer()
                Text(rangeLabel(review))
                    .font(Fonts.mono(15, weight: .semibold))
                    .foregroundStyle(Colors.text)
                Spacer()
                pagingButton("chevron.right", label: "Next week") {
                    weekStart = WeeklyReview.weekStart(after: weekStart)
                }
            }
            Text(review.countsLabel)
                .font(Fonts.mono(13))
                .foregroundStyle(Colors.accent)
            Text(review.attendedLabel)
                .font(Fonts.mono(12))
                .foregroundStyle(Colors.textSecondary)
        }
        .accessibilityElement(children: .contain)
    }

    private func pagingButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Colors.text)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func section(_ title: String, items: [AgendaItem], empty: String) -> some View {
        Section {
            if items.isEmpty {
                Text(empty)
                    .font(Fonts.mono(12))
                    .foregroundStyle(Colors.textSecondary)
                    .listRowBackground(Colors.background)
                    .listRowSeparatorTint(Colors.separator)
            } else {
                ForEach(items) { item in
                    Button {
                        selectedItem = item
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AgendaFormat.shortDate(item.occurrence))
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
        } header: {
            Text(title.uppercased())
                .font(Fonts.mono(11))
                .tracking(2)
                .foregroundStyle(Colors.textSecondary)
        }
    }

    private func rangeLabel(_ review: WeeklyReview) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        let last = Calendar(identifier: .gregorian).startOfDay(for: review.range.upperBound)
        return "\(formatter.string(from: review.weekStart)) – \(formatter.string(from: last))"
    }
}
