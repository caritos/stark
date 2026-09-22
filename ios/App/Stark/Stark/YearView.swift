// ios/App/Stark/Stark/YearView.swift
import SwiftUI
import StarkKit

/// The year mode: a year title with chevrons, a scrolling two-column grid of the twelve
/// mini-months, and the drag bar underneath (dragging it up, or tapping it, returns to month).
///
/// Each mini-month is a Sunday-first 6 x 7 block of real dates (`MonthGrid.days`), neighbouring
/// months' days dimmed and never tinted. A day with items is tinted `Colors.accent` at one of
/// three strengths by `DayDensity.level` (1 / 2-3 / 4+ items); today is the filled accent square
/// (on whichever cell it falls, in the month or not). Every day is a real `Button` selecting that
/// date; `ContentView` then returns to month mode and scrolls the agenda.
///
/// The counts come from `yearDensity` (the same `buildAgendaItems` as the month grid) computed
/// off the main actor, never in `body`, and all twelve months of the shown year are loaded into
/// the store, or their days would silently show as empty.
struct YearView: View {
    @EnvironmentObject private var store: PlannerStore
    /// The year on screen. Starts as the selected day's year; the chevrons change it.
    @State private var year: Int
    /// The last computed density, tagged with the year it belongs to (see `MonthGridView`).
    @State private var density: DensitySnapshot?
    let today: Date
    @Binding var mode: CalendarMode
    let onSelectDate: (Date) -> Void

    private static let cellHeight: CGFloat = 20
    /// Accent opacity of the tint for `DayDensity.level` 1, 2 and 3.
    private static let tintLow = 0.15
    private static let tintMedium = 0.30
    private static let tintHigh = 0.50
    private static let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private static let monthNames = Calendar(identifier: .gregorian).standaloneMonthSymbols
    private let monthColumns = Array(repeating: GridItem(.flexible(), spacing: Spacing.md, alignment: .top), count: 2)
    private let dayColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    init(today: Date, selectedDate: Date, mode: Binding<CalendarMode>, onSelectDate: @escaping (Date) -> Void) {
        self.today = today
        self._mode = mode
        self.onSelectDate = onSelectDate
        self._year = State(initialValue: YearMonth(date: selectedDate).year)
    }

    /// One day cell of one mini-month. The same date shows up in two mini-months (as a day of its
    /// own month and as a neighbouring day of the adjacent one), so the identity carries the
    /// month: `(month, iso)` is unique across all twelve blocks.
    private struct YearCell: Identifiable {
        let month0: Int
        let day: GridDay
        var id: String { "\(month0)-\(day.iso)" }
    }

    var body: some View {
        let todayIso = DateMath.isoDate(from: today)
        // Only a snapshot computed for the year on screen is used, so paging never flashes the
        // previous year's tint on the new year's days while the new counts are computed.
        let visibleDensity = density?.year == year ? density?.days ?? [:] : [:]

        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVGrid(columns: monthColumns, spacing: Spacing.md) {
                    ForEach(0..<12, id: \.self) { month0 in
                        miniMonth(month0, todayIso: todayIso, density: visibleDensity)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }

            #if !targetEnvironment(macCatalyst)
            ModeHandle(mode: $mode)
            #endif
        }
        .background(Colors.background)
        // Every month of the year the screen shows must be in the store. Runs on appear and
        // again whenever the year changes.
        .task(id: year) {
            store.loadMonths(covering: YearGrid.range(year: year))
        }
        // Recompute when (and only when) the year, today, or the store's items change; off the
        // main actor, and a stale result (the id changed while it ran) is dropped.
        .task(id: densityInputs) {
            // Debounce: the detached computation below cannot be cancelled, so tapping ‹/› quickly
            // would otherwise run one full-year `yearDensity` per tap. `.task(id:)` cancels this
            // task on every new id, so a rapid burst wakes up only once, for the last year.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let inputs = densityInputs
            let events = inputs.events
            let reminders = inputs.reminders
            let today = inputs.today
            let year = inputs.year
            let days = await Task.detached(priority: .userInitiated) {
                yearDensity(events: events, reminders: reminders, year: year, today: today)
            }.value
            guard !Task.isCancelled else { return }
            density = DensitySnapshot(year: year, days: days)
        }
    }

    /// Everything the density depends on. It is the `.task(id:)`, so the density is recomputed
    /// exactly when one of these changes.
    private struct DensityInputs: Equatable {
        let year: Int
        let today: Date
        let events: [Event]
        let reminders: [Reminder]
    }

    private struct DensitySnapshot {
        let year: Int
        /// Keyed by ISO date (`yyyy-MM-dd`), only days of that year with something on them.
        let days: [String: DayDensity]
    }

    private var densityInputs: DensityInputs {
        DensityInputs(year: year, today: today, events: store.events, reminders: store.reminders)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(String(year))
                .font(Fonts.mono(11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Colors.text)
                .padding(.leading, Spacing.sm)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            chevron("‹", label: "Previous year") { year -= 1 }
            chevron("›", label: "Next year") { year += 1 }
        }
        .padding(.horizontal, Spacing.sm)
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

    private func miniMonth(_ month0: Int, todayIso: String, density: [String: DayDensity]) -> some View {
        let cells = MonthGrid.days(for: YearMonth(year: year, month0: month0))
            .map { YearCell(month0: month0, day: $0) }
        return VStack(spacing: 0) {
            Text(Self.monthNames[month0].uppercased())
                .font(Fonts.mono(11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 24)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: dayColumns, spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(Self.weekdayLabels[index])
                        .font(Fonts.mono(9))
                        .foregroundStyle(Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 14)
                        .accessibilityHidden(true)
                }
            }

            LazyVGrid(columns: dayColumns, spacing: 0) {
                ForEach(cells) { cell in
                    dayCell(cell.day, isToday: cell.day.iso == todayIso, counts: density[cell.day.iso] ?? .none)
                }
            }
        }
    }

    private func dayCell(_ day: GridDay, isToday: Bool, counts: DayDensity) -> some View {
        Button {
            // A neighbouring month's cell still selects its own (real) date.
            onSelectDate(day.date)
        } label: {
            Text("\(day.day)")
                .font(Fonts.mono(11))
                .foregroundStyle(isToday ? Colors.background : (day.isInMonth ? Colors.text : Colors.textSecondary))
                .frame(maxWidth: .infinity, minHeight: Self.cellHeight, maxHeight: Self.cellHeight)
                .background {
                    if isToday {
                        Rectangle().fill(Colors.accent)
                    } else if day.isInMonth, let opacity = Self.tintOpacity(level: counts.level) {
                        Rectangle().fill(Colors.accent.opacity(opacity))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(counts.accessibilityLabel(title: AgendaFormat.monthDay(day.date), isToday: isToday))
        // A neighbouring-month day duplicates a label that exists in its own month's block; it
        // stays tappable for touch but VoiceOver skips it.
        .accessibilityHidden(!day.isInMonth)
    }

    /// The accent opacity for a `DayDensity.level`, nil for an empty day.
    private static func tintOpacity(level: Int) -> Double? {
        switch level {
        case 1: return tintLow
        case 2: return tintMedium
        case 3...: return tintHigh
        default: return nil
        }
    }
}
