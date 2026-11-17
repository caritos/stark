// ios/App/Stark/Stark/MonthGridView.swift
import SwiftUI
import StarkKit

/// Fixed-height, Sunday-first month grid, always 6 rows x 7 columns. The cells before day 1 and
/// after the month's last day show the neighbouring months' real dates, dimmed
/// (`Colors.textSecondary`), with their busyness lines; tapping one selects it and scrolls the
/// agenda, but the grid stays on the visible month (only the chevrons page). Today is a filled
/// accent square (on whichever cell it falls, in the month or not), the selected day (when it
/// isn't today) an outlined one.
///
/// Under each day number sit two 1 pt lines (issue #110, replacing the old dot markers): purple
/// (`Colors.eventDot`) for events, accent for tasks, each as wide as its own load (a third, two
/// thirds or all of the number's width for 1 / 2-3 / 4+ items) and absent when there are none. The
/// counts come from `gridDensity`, i.e. from the same Apple rows and plans the agenda uses
/// (`agendaWithApple`), so the grid can't disagree with the list. The block keeps its height on an empty day, and sits below
/// the number's square so the lines stay visible on today's filled cell.
///
/// In `.week` mode (the collapsed state) the grid is one row: the Sunday-first week of
/// `selectedDate`, drawn with the same cells. The title is the selected day's month and the
/// chevrons step the selection by a week (through `onSelectDate`, so the agenda follows) instead
/// of paging months. `visibleMonth` follows the selected day's month while in week mode and when
/// returning to month, so the density snapshot and the Apple fetch always cover the
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
    @Environment(AppleOverlayModel.self) private var overlay
    /// Apple reminders' plan blocks (sidecar), counted with Stark's own like the agenda does.
    @Environment(PlanCache.self) private var planCache
    @State private var visibleMonth = YearMonth(date: Date())
    /// The last computed density, tagged with the month it belongs to. Recomputed only when its
    /// inputs change (see `DensityInputs`), never in `body`: `body` re-runs on unrelated updates
    /// (a pending-completion tick, a sheet opening) and the computation walks every recurring
    /// event and reminder.
    @State private var density: DensitySnapshot?
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
    private static let rowHeight: CGFloat = 46
    private static let cellSize: CGFloat = 30
    private static let tintLow = 0.15
    private static let tintMedium = 0.30
    private static let tintHigh = 0.50
    /// The grid is always 6 full rows (42 cells), which keeps the grid and the agenda below it
    /// from resizing as the user pages between months.
    private static let maxRows = MonthGrid.dayCount / 7
    private static let weekdayLabels = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    private static let dotSize: CGFloat = 4
    /// Fixed height of the dots/check block under each number.
    private static let markHeight: CGFloat = 8
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let todayIso = DateMath.isoDate(from: today)
        let selectedIso = DateMath.isoDate(from: selectedDate)
        // Only a snapshot computed for the month on screen is used, so paging never flashes the
        // previous month's lines on the new month's days while the new ones are computed.
        let visibleDensity = density?.month == visibleMonth ? density?.days ?? [:] : [:]
        let isWeek = mode == .week
        let cells = isWeek ? MonthGrid.weekRow(containing: selectedDate) : MonthGrid.days(for: visibleMonth)

        VStack(spacing: 0) {
            header

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(Self.weekdayLabels[index])
                        .font(Fonts.mono(12))
                        .foregroundStyle(index == todayWeekdayIndex ? Colors.accent : Colors.textSecondary)
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
                        isSelected: day.iso == selectedIso,
                        counts: visibleDensity[day.iso] ?? .none
                    )
                }
            }
            // Fixed height either way, so the agenda below never jiggles; the change between one
            // row and six animates with the mode switch, and cells leaving mid-animation are
            // clipped rather than drawn over the drag bar.
            .frame(height: Self.rowHeight * CGFloat(isWeek ? 1 : Self.maxRows), alignment: .top)
            // The selected day's week row sits on a light rounded band (month mode only; in week
            // mode the single row is the whole grid).
            .background(alignment: .top) {
                if !isWeek, let row = selectedRow(in: cells, selectedIso: selectedIso) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Colors.separator.opacity(0.35))
                        .frame(height: Self.rowHeight)
                        .offset(y: Self.rowHeight * CGFloat(row))
                }
            }
            .clipped()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .background(Colors.background)
        .task { loadVisibleMonths() }
        // Recompute when (and only when) the month, today, the Apple snapshot or the plans change.
        // Equal arrays share a buffer, so the comparison SwiftUI makes on every `body` is cheap
        // until they really change. The work runs off the main actor, and a stale result
        // (the id changed while it ran) is dropped.
        .task(id: densityInputs) {
            let inputs = densityInputs
            let events = inputs.events
            let reminders = inputs.reminders
            let plans = inputs.plans
            let apple = inputs.apple
            let today = inputs.today
            let month = inputs.month
            let (year, month0) = (month.year, month.month0)
            let days = await Task.detached(priority: .userInitiated) {
                gridDensity(events: events, reminders: reminders, month: YearMonth(year: year, month0: month0), today: today, plans: plans, apple: apple)
            }.value
            guard !Task.isCancelled else { return }
            density = DensitySnapshot(month: month, days: days)
        }
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

    private var todayWeekdayIndex: Int { Calendar.current.component(.weekday, from: today) - 1 }

    /// The grid row (0-based) holding the selected day, if it is in the visible grid.
    private func selectedRow(in cells: [GridDay], selectedIso: String) -> Int? {
        cells.firstIndex { $0.iso == selectedIso }.map { $0 / 7 }
    }

    private func syncVisibleMonthToSelection() {
        visibleMonth = YearMonth(date: selectedDate)
        loadVisibleMonths()
    }

    /// The Apple overlay fetches every day the visible grid touches (its neighbouring days can be
    /// in the previous or next month); the dots arrive with the density recompute, which is
    /// asynchronous anyway.
    private func loadVisibleMonths() {
        let range = MonthGrid.range(for: visibleMonth)
        Task { await overlay.reload(for: .monthGrid, display: range, today: today) }
    }

    /// Everything the density depends on. It is the `.task(id:)`, so the density is recomputed
    /// exactly when one of these changes.
    private struct DensityInputs: Equatable {
        let month: YearMonth
        let today: Date
        let events: [Event]
        let reminders: [Reminder]
        let plans: [PlanBlock]
        let apple: AppleSnapshot
    }

    private struct DensitySnapshot {
        let month: YearMonth
        /// Keyed by ISO date (`yyyy-MM-dd`), covering every cell of the month's grid.
        let days: [String: DayDensity]
    }

    private var densityInputs: DensityInputs {
        DensityInputs(month: visibleMonth, today: today, events: [], reminders: [],
                      plans: planCache.applePlans,
                      apple: overlay.snapshot)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: goToToday) {
                (Text(monthTitle.month + " ").foregroundColor(Colors.text)
                    + Text(monthTitle.year).foregroundColor(Color.red))
                    .font(Fonts.mono(30, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.leading, Spacing.sm)
                    .padding(.trailing, Spacing.md)
                    .frame(minHeight: 52)
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
        .frame(minHeight: 52)
    }

    private func chevron(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(Fonts.mono(22))
                .foregroundStyle(Colors.accent)
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
            VStack(spacing: 0) {
                Text("\(day.day)")
                    .font(Fonts.mono(17))
                    .foregroundStyle(isToday ? Color.white : (day.isInMonth ? Colors.text : Colors.textSecondary))
                    .frame(width: Self.cellSize, height: Self.cellSize)
                    .background {
                        if isToday {
                            Circle().fill(Colors.accent)
                        } else if isSelected {
                            Circle().strokeBorder(Colors.accent, lineWidth: 1.5)
                        }
                    }
                busyBar(for: counts)
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

    /// Up to five 4 pt dots in the day's calendar colours (one `Colors.eventDot` dot when there
    /// are events but no colour, i.e. Stark's own events), then a small check-square glyph when
    /// the day has tasks. The block always has the same height so rows don't shift.
    private func busyBar(for counts: DayDensity) -> some View {
        let colors: [Color] = !counts.eventColors.isEmpty
            ? counts.eventColors.prefix(5).map { Color(hex: $0) }
            : (counts.events > 0 ? [Colors.eventDot] : [])
        return HStack(spacing: 2) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                Circle().fill(c).frame(width: Self.dotSize, height: Self.dotSize)
            }
            if counts.tasks > 0 {
                Image(systemName: "checkmark.square")
                    .font(.system(size: 7))
                    .foregroundStyle(Colors.accent)
            }
        }
        .frame(height: Self.markHeight)
        .padding(.top, 1)
    }

    private var monthTitle: (month: String, year: String) {
        // Week mode names the selected day's month (read from the selection itself, so it is
        // right on the very frame the selection changes, before `visibleMonth` has caught up).
        let date = mode == .week
            ? selectedDate
            : DateMath.date(from: DateMath.isoDate(year: visibleMonth.year, month0: visibleMonth.month0, day: 1))
        let parts = AgendaFormat.monthYear(date).split(separator: " ", maxSplits: 1).map(String.init)
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
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
