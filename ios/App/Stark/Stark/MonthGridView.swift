// ios/App/Stark/Stark/MonthGridView.swift
import SwiftUI
import StarkKit

/// Fixed-height, Sunday-first month grid, always 6 rows x 7 columns. The cells before day 1 and
/// after the month's last day show the neighbouring months' real dates, dimmed
/// (`Colors.textSecondary`); tapping one selects it and scrolls the
/// agenda, but the grid stays on the visible month (only the chevrons page). Today is a filled
/// accent square (on whichever cell it falls, in the month or not), the selected day (when it
/// isn't today) an outlined one.
///
/// In `.week` mode (the collapsed state) the grid is one row: the Sunday-first week of
/// `selectedDate`, drawn with the same cells. The title is the selected day's month and the
/// chevrons step the selection by a week (through `onSelectDate`, so the agenda follows) instead
/// of paging months. `visibleMonth` follows the selected day's month while in week mode and when
/// returning to month, so the store's loaded months always cover the
/// week on screen (the week lies inside its month's 6-row grid). In `.month` mode a plain
/// selection (a tap) never changes `visibleMonth` — but `scrollPagingDate` does (issue #101),
/// since scrolling the agenda is deliberately allowed to page the month grid even though tapping
/// it is not.
/// A request to page the month grid to a date's month. A fresh `token` per request makes
/// scrolling back to the same day twice a *different* value, so `onChange` fires (and pages)
/// again — see `scrollPagingDate`. Mirrors `ScrollRequest` in `AgendaView.swift`.
struct GridPagingRequest: Equatable {
    let date: Date
    let token = UUID()
}

struct MonthGridView: View {
    @EnvironmentObject private var store: PlannerStore
    @State private var visibleMonth = YearMonth(date: Date())
    /// Passed in (not read from `Date()` here) so the highlight moves when the day changes.
    let today: Date
    /// `.week` shows one row, anything else the full month grid (`.year` is passed too, while the
    /// screen is showing the year view and this grid is hidden underneath).
    let mode: CalendarMode
    let selectedDate: Date
    let onSelectDate: (Date) -> Void
    /// Set by `ContentView` only from `AgendaView.onDayInView` (never from a tap) — pages
    /// `visibleMonth` to follow the agenda's scroll position, but only in month mode. Structurally
    /// separate from `selectedDate`/`onSelectDate` (the tap path) so a tap can never accidentally
    /// page the month grid (issue #96), and a scroll can never accidentally suppress itself
    /// (issue #101). Carries a token (mirroring `ScrollRequest` in `AgendaView.swift`) so scrolling
    /// back to a day that equals the last-reported one still forces a re-page — scroll always wins
    /// over an independent chevron browse (`changeMonth`), which pages `visibleMonth` without
    /// touching this property at all. Without the token, browsing ahead with the chevrons and then
    /// scrolling the agenda back to the same day already reported here would silently leave the
    /// grid stuck on the chevron-browsed month, since `.onChange` only fires on a real value change.
    let scrollPagingDate: GridPagingRequest?

    /// The number's square plus a little air.
    private static let rowHeight: CGFloat = 34
    private static let cellSize: CGFloat = 30
    /// The grid is always 6 full rows (42 cells), which keeps the grid and the agenda below it
    /// from resizing as the user pages between months.
    private static let maxRows = MonthGrid.dayCount / 7
    private static let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let todayIso = DateMath.isoDate(from: today)
        let selectedIso = DateMath.isoDate(from: selectedDate)
        let isWeek = mode == .week
        let cells = isWeek ? MonthGrid.weekRow(containing: selectedDate) : MonthGrid.days(for: visibleMonth)

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
                // 42 cells (7 in week mode), each a real date (`GridDay` is Identifiable by its
                // ISO date, so the ids are unique even across the month boundaries).
                ForEach(cells) { day in
                    dayCell(
                        day: day,
                        isToday: day.iso == todayIso,
                        isSelected: day.iso == selectedIso
                    )
                }
            }
            // Fixed height either way, so the agenda below never jiggles; the change between one
            // row and six animates with the mode switch, and cells leaving mid-animation are
            // clipped rather than drawn over the drag bar.
            .frame(height: Self.rowHeight * CGFloat(isWeek ? 1 : Self.maxRows), alignment: .top)
            .clipped()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .background(Colors.background)
        .task { loadVisibleMonths() }
        // The day rolled over: if the grid was showing the old today's month, show the new one's.
        // (Not in week mode: there `visibleMonth` follows the selected day, not today.)
        .onChange(of: today) { oldToday, newToday in
            guard mode != .week, visibleMonth == YearMonth(date: oldToday) else { return }
            visibleMonth = YearMonth(date: newToday)
            loadVisibleMonths()
        }
        // Entering week mode, or coming back to month, lands on the selected day's month.
        .onChange(of: mode) { _, _ in syncVisibleMonthToSelection() }
        // In week mode the week row follows the selection, possibly into another month (the
        // chevrons, a day tap, the midnight follow). In month mode a plain selection never pages.
        .onChange(of: selectedDate) { _, _ in
            guard mode == .week else { return }
            syncVisibleMonthToSelection()
        }
        // Scroll-driven paging (issue #101): unlike a plain selection, this pages the month grid
        // — a deliberate, scroll-only exception to "a tap never pages the month view" (issue #96).
        // Scroll always wins over an independent chevron browse (changeMonth) — see
        // GridPagingRequest's doc comment for why the token matters here.
        .onChange(of: scrollPagingDate) { _, newValue in
            guard mode == .month, let newValue else { return }
            visibleMonth = YearMonth(date: newValue.date)
            loadVisibleMonths()
        }
    }

    private func syncVisibleMonthToSelection() {
        visibleMonth = YearMonth(date: selectedDate)
        loadVisibleMonths()
    }

    /// The store must have loaded every month the visible grid touches (its neighbouring days
    /// can be in the previous or next month's file).
    private func loadVisibleMonths() {
        store.loadMonths(covering: MonthGrid.range(for: visibleMonth))
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: goToToday) {
                Text(monthTitle)
                    .font(Fonts.mono(11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Colors.text)
                    .padding(.leading, Spacing.sm)
                    .padding(.trailing, Spacing.md)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Goes to today")
            Spacer()
            if mode == .week {
                chevron("‹", label: "Previous week") { onSelectDate(MonthGrid.weekStepped(selectedDate, by: -1)) }
                chevron("›", label: "Next week") { onSelectDate(MonthGrid.weekStepped(selectedDate, by: 1)) }
            } else {
                chevron("‹", label: "Previous month") { changeMonth(by: -1) }
                chevron("›", label: "Next month") { changeMonth(by: 1) }
            }
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

    private func dayCell(day: GridDay, isToday: Bool, isSelected: Bool) -> some View {
        Button {
            // A neighbouring month's cell selects that date and scrolls the agenda; the grid
            // stays on the visible month (only the chevrons page).
            onSelectDate(day.date)
        } label: {
            VStack(spacing: 0) {
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
            }
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // In-month cells read "15" (unchanged); a neighbouring month's cell names its month.
        .accessibilityLabel(
            (day.isInMonth ? "\(day.day)" : AgendaFormat.monthDay(day.date)) + (isToday ? ", today" : "")
        )
    }

    private var monthTitle: String {
        // Week mode names the selected day's month (read from the selection itself, so it is
        // right on the very frame the selection changes, before `visibleMonth` has caught up).
        if mode == .week { return AgendaFormat.monthYear(selectedDate).uppercased() }
        let first = DateMath.date(from: DateMath.isoDate(year: visibleMonth.year, month0: visibleMonth.month0, day: 1))
        return AgendaFormat.monthYear(first).uppercased()
    }

    /// Tapping the month title returns to today: selects it (which scrolls the agenda there and
    /// re-centres the window if today is outside it) and pages the grid back to today's month.
    /// Unlike tapping a day cell, which never pages the grid (issue #96), this is an explicit
    /// "take me back", so the grid follows. In week mode `visibleMonth` already follows the
    /// selected day, so setting it here is harmless.
    private func goToToday() {
        onSelectDate(today)
        visibleMonth = YearMonth(date: today)
        loadVisibleMonths()
    }

    private func changeMonth(by offset: Int) {
        visibleMonth = YearMonth(year: visibleMonth.year, month0: visibleMonth.month0 + offset)
        loadVisibleMonths()
    }
}
