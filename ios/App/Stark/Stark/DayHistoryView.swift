// ios/App/Stark/Stark/DayHistoryView.swift
import SwiftUI
import StarkKit

/// Read-only look back at a day's plan (`DayHistory` in StarkKit): the day's events, the planned
/// blocks whose task got done (dimmed, checked, struck through) and those that did not (outlined
/// accent, MISSED on a past day, OPEN today), with the numbers under the title and the week.
/// Opened on `today` from the planner; ‹ › step by day, › stops at `today`. Nothing here edits a
/// plan or a task. `today` is passed in; the view never reads `Date()`.
struct DayHistoryView: View {
    let today: Date
    @State private var day: Date

    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss

    private static let calendar = Calendar(identifier: .gregorian)
    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.dateFormat = "EEE MMM d"
        return f
    }()

    init(day: Date, today: Date) {
        self.today = today
        _day = State(initialValue: Calendar(identifier: .gregorian).startOfDay(for: day))
    }

    private var cal: Calendar { Self.calendar }
    private var dayStart: Date { cal.startOfDay(for: day) }
    private var isToday: Bool { cal.isDate(day, inSameDayAs: today) }

    private var history: DayHistory {
        DayHistory.make(day: day, events: store.events, reminders: store.reminders, plans: store.plans, today: today)
    }
    private var weekStats: DayHistory.Stats {
        DayHistory.weekStats(containing: day, reminders: store.reminders, plans: store.plans, today: today)
    }

    var body: some View {
        let history = history
        NavigationStack {
            VStack(spacing: 0) {
                header(history)
                PastDayView(day: day, history: history, isToday: isToday)
            }
            .background(Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("HISTORY")
                        .font(Fonts.mono(12)).tracking(2)
                        .foregroundStyle(Colors.text)
                        .accessibilityAddTraits(.isHeader)
                }
                SquareToolbarButton(systemImage: "xmark", label: "Close", placement: .cancellationAction) { dismiss() }
            }
        }
        .tint(Colors.accent)
        .preferredColorScheme(.dark)
        .task(id: day) { loadMonths() }
    }

    // MARK: Loading

    /// The day's Sunday-Saturday week, widened back by the overdue lookback (for the week line
    /// and so completed copies and recurring series are in memory).
    private func loadMonths() {
        let weekday = cal.component(.weekday, from: dayStart)
        let sunday = cal.date(byAdding: .day, value: -(weekday - 1), to: dayStart) ?? dayStart
        let saturday = cal.date(byAdding: .day, value: 6, to: sunday) ?? dayStart
        let lower = AgendaWindow.loadRange(around: sunday).lowerBound
        let upper = AgendaWindow.loadRange(around: saturday).upperBound
        store.loadMonths(covering: lower...upper)
    }

    private func step(_ days: Int) {
        guard let next = cal.date(byAdding: .day, value: days, to: dayStart), next <= cal.startOfDay(for: today) else { return }
        day = next
    }

    // MARK: Header

    private var dayWord: String {
        if isToday { return "TODAY" }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: today)),
           cal.isDate(day, inSameDayAs: yesterday) { return "YESTERDAY" }
        return ""
    }

    private func numbers(_ h: DayHistory) -> String {
        guard h.stats.hasPlan else { return "NO PLAN" }
        var s = "\(DayHistory.minutesText(h.stats.plannedMinutes)) planned - \(DayHistory.minutesText(h.stats.doneMinutes)) done"
        if let c = h.stats.completion { s += " - \(Int((c * 100).rounded()))%" }
        return s
    }

    private func header(_ h: DayHistory) -> some View {
        HStack(spacing: 0) {
            arrow("chevron.left", label: "Previous day", disabled: false) { step(-1) }
            VStack(spacing: 3) {
                (Text(dayWord).fontWeight(.bold) + Text("\(dayWord.isEmpty ? "" : "  ")\(Self.titleFormatter.string(from: day).uppercased())"))
                    .font(Fonts.mono(12)).tracking(2)
                    .foregroundStyle(Colors.text)
                    .accessibilityAddTraits(.isHeader)
                if let line = DayHistory.summaryLine(stats: h.stats, isToday: isToday) {
                    Text(line).font(Fonts.mono(10)).tracking(1.5).foregroundStyle(Colors.accent)
                }
                Text(numbers(h)).font(Fonts.mono(10)).foregroundStyle(Colors.textSecondary)
                if let week = DayHistory.weekLine(weekStats) {
                    Text(week).font(Fonts.mono(9)).tracking(1).foregroundStyle(Colors.textSecondary.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            arrow("chevron.right", label: "Next day", disabled: isToday) { step(1) }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
    }

    private func arrow(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(disabled ? Colors.textSecondary.opacity(0.3) : Colors.text)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}
