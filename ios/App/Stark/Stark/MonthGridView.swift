// ios/App/Stark/Stark/MonthGridView.swift
import SwiftUI
import StarkKit

/// Fixed-height, Sunday-first month grid, always 6 rows x 7 columns. The cells before day 1 and
/// after the month's last day show the neighbouring months' real dates, dimmed
/// (`Colors.textSecondary`), with their density markers; tapping one selects it and scrolls the
/// agenda, but the grid stays on the visible month (only the chevrons page). Today is a filled
/// accent square (on whichever cell it falls, in the month or not), the selected day (when it
/// isn't today) an outlined one.
///
/// Under each day number sits a row of density markers (flat 4pt squares, no circles): up to
/// `maxMarkers` accent ones for tasks, then up to `maxMarkers` `Colors.eventDot` ones for events.
/// The counts come from `gridDensity`, i.e. from the same `buildAgendaItems` the agenda uses, so
/// the grid can't disagree with the list. The marker row keeps its height on an empty day, and
/// sits below the number's square so an accent marker stays visible on today's filled cell.
struct MonthGridView: View {
    @EnvironmentObject private var store: PlannerStore
    @State private var visibleMonth = YearMonth(date: Date())
    /// The last computed density, tagged with the month it belongs to. Recomputed only when its
    /// inputs change (see `DensityInputs`), never in `body`: `body` re-runs on unrelated updates
    /// (a pending-completion tick, a sheet opening) and the computation walks every recurring
    /// event and reminder.
    @State private var density: DensitySnapshot?
    /// Passed in (not read from `Date()` here) so the highlight moves when the day changes.
    let today: Date
    let selectedDate: Date
    let onSelectDate: (Date) -> Void

    /// The number's square, then a small gap, then the marker row, with a point of air each side.
    private static let rowHeight: CGFloat = 38
    private static let cellSize: CGFloat = 30
    private static let markerSize: CGFloat = Spacing.xs
    private static let markerSpacing: CGFloat = 2
    private static let markerGap: CGFloat = 2
    /// Markers drawn per kind. The counts themselves are uncapped (VoiceOver reads the truth).
    private static let maxMarkers = 3
    /// A month spans at most 6 week-rows; always reserving all 6 keeps the grid (and so the
    /// agenda below it) from resizing as the user pages between months.
    private static let maxRows = 6
    private static let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let todayIso = DateMath.isoDate(from: today)
        let selectedIso = DateMath.isoDate(from: selectedDate)
        // Only a snapshot computed for the month on screen is used, so paging never flashes the
        // previous month's markers on the new month's days while the new ones are computed.
        let visibleDensity = density?.month == visibleMonth ? density?.days ?? [:] : [:]

        VStack(spacing: 0) {
            header

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(Self.weekdayLabels[index])
                        .font(Fonts.mono(11))
                        .foregroundStyle(Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 20)
                }
            }

            LazyVGrid(columns: columns, spacing: 0) {
                // 42 cells, each a real date (`GridDay` is Identifiable by its ISO date, so the
                // ids are unique even across the month boundaries).
                ForEach(MonthGrid.days(for: visibleMonth)) { day in
                    dayCell(
                        day: day,
                        isToday: day.iso == todayIso,
                        isSelected: day.iso == selectedIso,
                        counts: visibleDensity[day.iso] ?? .none
                    )
                }
            }
            .frame(height: Self.rowHeight * CGFloat(Self.maxRows), alignment: .top)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .background(Colors.background)
        .task { store.loadMonths(covering: MonthGrid.range(for: visibleMonth)) }
        // Recompute when (and only when) the month, today, or the store's items change. Equal
        // arrays share a buffer, so the comparison SwiftUI makes on every `body` is cheap until
        // the store really republishes. The work runs off the main actor, and a stale result
        // (the id changed while it ran) is dropped.
        .task(id: densityInputs) {
            let inputs = densityInputs
            let events = inputs.events
            let reminders = inputs.reminders
            let today = inputs.today
            let month = inputs.month
            let (year, month0) = (month.year, month.month0)
            let days = await Task.detached(priority: .userInitiated) {
                gridDensity(events: events, reminders: reminders, month: YearMonth(year: year, month0: month0), today: today)
            }.value
            guard !Task.isCancelled else { return }
            density = DensitySnapshot(month: month, days: days)
        }
        // The day rolled over: if the grid was showing the old today's month, show the new one's.
        .onChange(of: today) { oldToday, newToday in
            guard visibleMonth == YearMonth(date: oldToday) else { return }
            visibleMonth = YearMonth(date: newToday)
            store.loadMonths(covering: MonthGrid.range(for: visibleMonth))
        }
    }

    /// Everything the density depends on. It is the `.task(id:)`, so the density is recomputed
    /// exactly when one of these changes.
    private struct DensityInputs: Equatable {
        let month: YearMonth
        let today: Date
        let events: [Event]
        let reminders: [Reminder]
    }

    private struct DensitySnapshot {
        let month: YearMonth
        /// Keyed by ISO date (`yyyy-MM-dd`), covering every cell of the month's grid.
        let days: [String: DayDensity]
    }

    private var densityInputs: DensityInputs {
        DensityInputs(month: visibleMonth, today: today, events: store.events, reminders: store.reminders)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(monthTitle)
                .font(Fonts.mono(11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Colors.text)
                .padding(.leading, Spacing.sm)
            Spacer()
            chevron("‹", label: "Previous month") { changeMonth(by: -1) }
            chevron("›", label: "Next month") { changeMonth(by: 1) }
        }
        .frame(height: 44)
    }

    private func chevron(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(Fonts.mono(22))
                .foregroundStyle(Colors.text)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func dayCell(day: GridDay, isToday: Bool, isSelected: Bool, counts: DayDensity) -> some View {
        Button {
            // A neighbouring month's cell selects that date and scrolls the agenda; the grid
            // stays on the visible month (only the chevrons page).
            onSelectDate(day.date)
        } label: {
            VStack(spacing: Self.markerGap) {
                Text("\(day.day)")
                    .font(Fonts.mono(15))
                    .foregroundStyle(isToday ? Colors.background : (day.isInMonth ? Colors.text : Colors.textSecondary))
                    .frame(width: Self.cellSize, height: Self.cellSize)
                    .background {
                        if isToday {
                            Rectangle().fill(Colors.accent)
                        } else if isSelected {
                            Rectangle().strokeBorder(Colors.accent, lineWidth: 1)
                        }
                    }
                // Outside the number's square (which is filled on today), so an accent marker
                // still shows on today's cell.
                markers(for: counts)
            }
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // In-month cells read "15" (unchanged); a neighbouring month's cell names its month.
        .accessibilityLabel(counts.accessibilityLabel(
            title: day.isInMonth ? "\(day.day)" : AgendaFormat.monthDay(day.date),
            isToday: isToday
        ))
    }

    /// Up to `maxMarkers` task squares then up to `maxMarkers` event squares. The row is always
    /// `markerSize` tall, even with nothing to draw, so a cell's height never depends on content.
    private func markers(for counts: DayDensity) -> some View {
        HStack(spacing: Self.markerSpacing) {
            ForEach(0..<min(counts.tasks, Self.maxMarkers), id: \.self) { _ in
                Rectangle().fill(Colors.accent).frame(width: Self.markerSize, height: Self.markerSize)
            }
            ForEach(0..<min(counts.events, Self.maxMarkers), id: \.self) { _ in
                Rectangle().fill(Colors.eventDot).frame(width: Self.markerSize, height: Self.markerSize)
            }
        }
        .frame(height: Self.markerSize)
    }

    private var monthTitle: String {
        let first = DateMath.date(from: DateMath.isoDate(year: visibleMonth.year, month0: visibleMonth.month0, day: 1))
        return AgendaFormat.monthYear(first).uppercased()
    }

    private func changeMonth(by offset: Int) {
        visibleMonth = YearMonth(year: visibleMonth.year, month0: visibleMonth.month0 + offset)
        store.loadMonths(covering: MonthGrid.range(for: visibleMonth))
    }
}
