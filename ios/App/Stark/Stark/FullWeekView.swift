// ios/App/Stark/Stark/FullWeekView.swift
import SwiftUI
import StarkKit

/// The full-screen Week (Fantastical's Week view): a "November 2026" title (year in red, the month
/// of the week's Wednesday) with chevrons, seven columns from the Sunday on or before the selected
/// day, each headed by its caps weekday and day number (today: red weekday, blue circle, pale blue
/// column), an all-day strip, then the shared scrolling 24-hour `HourGrid` with column hairlines,
/// the timed blocks per column and, in a week holding today, the red now-line across with its dot
/// in today's column.
///
/// Each column is laid out exactly as the Day: the Apple snapshot with the sidecar's plans
/// (`agendaWithApple`) over that day, then `timelineLayout`, all off the main actor and debounced, tagged with the week shown.
/// Read-only: a tap on a block or chip opens the agenda row's detail sheet (`onOpenItem`), a tap on
/// a column header returns to the DayTicker on that day (`onSelectDate`). Chevrons and horizontal
/// swipes step one week.
struct FullWeekView: View {
    @Environment(AppleOverlayModel.self) private var overlay
    @Environment(PlanCache.self) private var planCache
    @Environment(WeatherModel.self) private var weather
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    /// Start of the week's Sunday.
    @State private var weekStart: Date
    @State private var snapshot: LayoutSnapshot?
    let today: Date
    let onSelectDate: (Date) -> Void
    let onOpenItem: (AgendaItem) -> Void

    private typealias M = HourGridMetrics
    private static let calendar = Calendar(identifier: .gregorian)
    private static let weekdayLabels = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    /// All-day rows before a column's strip ends in "+N".
    private static let visibleChipRows = 3
    /// Under this column width a block shows its title only.
    private static let timeTextMinWidth: CGFloat = 60

    init(today: Date, selectedDate: Date, onSelectDate: @escaping (Date) -> Void,
         onOpenItem: @escaping (AgendaItem) -> Void) {
        self.today = today
        self.onSelectDate = onSelectDate
        self.onOpenItem = onOpenItem
        _weekStart = State(initialValue: Self.sunday(onOrBefore: selectedDate))
    }

    /// Start of the Sunday on or before `date` (the grids' week start).
    nonisolated static func sunday(onOrBefore date: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)  // 1 = Sunday
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: start) ?? start
    }

    nonisolated static func days(from weekStart: Date) -> [Date] {
        let calendar = Calendar(identifier: .gregorian)
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: weekStart) ?? weekStart }
    }

    private var days: [Date] { Self.days(from: weekStart) }

    /// Today's column, or nil when the week does not hold today.
    private var todayColumn: Int? {
        days.firstIndex { Self.calendar.isDate($0, inSameDayAs: today) }
    }

    var body: some View {
        let layout = snapshot?.weekStart == weekStart ? snapshot : nil
        VStack(spacing: 0) {
            header
            columnHeaders
            allDayStrip(layout)
            Rectangle().fill(Colors.separator).frame(height: 0.5)
            ScrollViewReader { scroller in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        HourGrid(columnCount: 7, nowColumn: todayColumn, highlightedColumn: todayColumn,
                                 showsColumnRules: true) { width in
                            blocks(layout, columnWidth: width)
                        }
                        // Invisible hour anchors for the initial scroll (string ids, see FullDayView).
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                Color.clear.frame(height: M.hourHeight).id(Self.anchorID(hour))
                            }
                        }
                        .padding(.top, M.topInset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .contentMargins(.bottom, FloatingBottomBar.clearance, for: .scrollContent)
                .onAppear { scrollToStart(scroller) }
                .onChange(of: weekStart) { _, _ in scrollToStart(scroller) }
            }
        }
        .background(Colors.card)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                    changeWeek(by: dx < 0 ? 1 : -1)
                }
        )
        .task(id: weekStart) {
            let range = Self.range(for: weekStart)
            await overlay.reload(for: .fullWeek, display: range, today: today)
        }
        .onDisappear {
            let today = today
            Task { await overlay.reload(for: .fullWeek, display: nil, today: today) }
        }
        // The day rolled over while Week showed the old today's week: follow it.
        .onChange(of: today) { oldToday, newToday in
            guard Self.sunday(onOrBefore: oldToday) == weekStart else { return }
            weekStart = Self.sunday(onOrBefore: newToday)
        }
        .task(id: layoutInputs) {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let inputs = layoutInputs
            let events = inputs.events, reminders = inputs.reminders, plans = inputs.plans
            let apple = inputs.apple, today = inputs.today, weekStart = inputs.weekStart
            let result = await Task.detached(priority: .userInitiated) {
                Self.computeLayout(events: events, reminders: reminders, plans: plans, apple: apple,
                                   weekStart: weekStart, today: today)
            }.value
            guard !Task.isCancelled else { return }
            snapshot = LayoutSnapshot(weekStart: weekStart, columns: result.columns, items: result.items)
        }
    }

    // MARK: - Data

    private struct LayoutInputs: Equatable {
        let weekStart: Date
        let today: Date
        let events: [Event]
        let reminders: [Reminder]
        let plans: [PlanBlock]
        let apple: AppleSnapshot
    }

    private struct LayoutSnapshot {
        let weekStart: Date
        /// One timeline per column, Sunday first.
        let columns: [DayTimeline]
        /// The agenda rows behind the blocks and chips, by column then id, for the detail sheet.
        let items: [[String: AgendaItem]]
    }

    private var layoutInputs: LayoutInputs {
        LayoutInputs(weekStart: weekStart, today: today, events: [], reminders: [],
                     plans: planCache.applePlans,
                     apple: overlay.snapshot)
    }

    /// The seven days, from Sunday's start to Saturday's last second.
    nonisolated static func range(for weekStart: Date) -> ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: weekStart)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        return start...end.addingTimeInterval(-1)
    }

    /// The same pipeline as `FullDayView`, over the whole week, laid out per column, so a
    /// multi-day or midnight-crossing event reads the same in both views.
    nonisolated private static func computeLayout(
        events: [Event], reminders: [Reminder], plans: [PlanBlock], apple: AppleSnapshot,
        weekStart: Date, today: Date
    ) -> (columns: [DayTimeline], items: [[String: AgendaItem]]) {
        let calendar = Calendar(identifier: .gregorian)
        var columns: [DayTimeline] = []
        var items: [[String: AgendaItem]] = []
        // Built once over the week, so the agenda's rules (a repeating reminder listed once) hold
        // across the columns; each column then keeps its own day's rows.
        let rows = timelineAgendaItems(events: events, reminders: reminders, plans: plans, apple: apple,
                                       days: range(for: weekStart), today: today, calendar: calendar)
        for day in days(from: weekStart) {
            let column = timelineLayout(items: rows, day: day, calendar: calendar)
            columns.append(column)
            items.append(column.items)
        }
        return (columns, items)
    }

    private static func anchorID(_ hour: Int) -> String { "week-hour-\(hour)" }

    private func changeWeek(by offset: Int) {
        weekStart = Self.calendar.date(byAdding: .day, value: 7 * offset, to: weekStart) ?? weekStart
    }

    /// A week holding today opens near now (an hour before, not earlier than 7 AM); another at 8 AM.
    private func scrollToStart(_ scroller: ScrollViewProxy) {
        let hour: Int
        if todayColumn != nil {
            let now = Self.calendar.component(.hour, from: Date())
            hour = min(23, max(now - 1, 7))
        } else {
            hour = 8
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            scroller.scrollTo(Self.anchorID(hour), anchor: .top)
        }
    }

    // MARK: - Header

    /// "November 2026": the month of the week's Wednesday, so a week split across two months is
    /// named after the one holding most of it.
    private var titleText: Text {
        let wednesday = Self.calendar.date(byAdding: .day, value: 3, to: weekStart) ?? weekStart
        let year = Self.calendar.component(.year, from: wednesday)
        return Text(AgendaFormat.monthName(wednesday) + " ").foregroundColor(Colors.text)
            + Text(String(year)).foregroundColor(Colors.yearRed)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button { weekStart = Self.sunday(onOrBefore: today) } label: {
                titleText
                    .font(Fonts.mono(30, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.leading, Spacing.md)
                    .padding(.trailing, Spacing.sm)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint("Goes to this week")
            Spacer(minLength: 0)
            chevron("‹", label: "Previous week") { changeWeek(by: -1) }
            chevron("›", label: "Next week") { changeWeek(by: 1) }
        }
        .padding(.trailing, Spacing.sm)
        .frame(minHeight: 52)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
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

    /// Caps weekday over the day number per column; today has a red weekday, the number in a
    /// blue circle and the pale blue column ground. A tap opens that day in the DayTicker.
    @ViewBuilder
    private var columnHeaders: some View {
        // The forecast row exists only while some day of this week has one, and then in every
        // column (an empty placeholder for a day without), so the headers stay level.
        let forecasts = days.map { weather.forecast(on: $0) }
        let showsForecast = !typeSize.isAccessibilitySize && forecasts.contains(where: { $0 != nil })
        HStack(spacing: 0) {
            Color.clear.frame(width: M.labelWidth, height: 1)
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let isToday = index == todayColumn
                Button { onSelectDate(day) } label: {
                    VStack(spacing: 2) {
                        Text(Self.weekdayLabels[index])
                            .font(Fonts.mono(12, weight: .medium))
                            .foregroundStyle(isToday ? Colors.yearRed : Colors.text)
                        Text("\(Self.calendar.component(.day, from: day))")
                            .font(Fonts.mono(17, weight: .semibold))
                            .foregroundStyle(isToday ? Color.white : Colors.text)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(isToday ? Colors.accent : Color.clear))
                        if showsForecast {
                            if let forecast = forecasts[index] {
                                WeatherMiniChip(weather: forecast)
                                    .accessibilityHidden(true)
                            } else {
                                Color.clear.frame(height: 14)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(isToday ? Colors.todayCell : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The button's label replaces its children's, so the forecast is spoken here.
                .accessibilityLabel(WeatherFormat.label(
                    AgendaFormat.weekdayName(day) + ", " + AgendaFormat.monthDay(day) + (isToday ? ", today" : ""),
                    weather: forecasts[index], locale: locale))
                .accessibilityHint("Opens this day in the DayTicker")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    // MARK: - All-day strip

    /// One row per chip across the week, as tall as the fullest column (at most
    /// `visibleChipRows`); a column with more ends in "+N", which opens that day in the DayTicker.
    @ViewBuilder
    private func allDayStrip(_ layout: LayoutSnapshot?) -> some View {
        let columns = layout?.columns ?? []
        let rows = min(Self.visibleChipRows, columns.map(\.allDay.count).max() ?? 0)
        if rows > 0 {
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: M.labelWidth, height: 1)
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let chips = index < columns.count ? columns[index].allDay : []
                    let overflows = chips.count > rows
                    let shown = overflows ? Array(chips.prefix(rows - 1)) : chips
                    VStack(spacing: 3) {
                        ForEach(shown) { chip in
                            Button { layout?.items[index][chip.id].map(onOpenItem) } label: {
                                TimelineChipView(chip: chip, compact: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(TimelineChipView.accessibilityText(chip))
                            .accessibilityHint("Opens details")
                        }
                        if overflows {
                            Button { onSelectDate(day) } label: {
                                TimelineMoreChipView(count: chips.count - shown.count, compact: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(chips.count - shown.count) more all-day items")
                            .accessibilityHint("Opens this day in the DayTicker")
                        }
                    }
                    .padding(.horizontal, 1)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.bottom, Spacing.xs)
        }
    }

    // MARK: - Blocks

    private func blocks(_ layout: LayoutSnapshot?, columnWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let layout {
                ForEach(Array(layout.columns.enumerated()), id: \.offset) { index, timeline in
                    let day = index < days.count ? days[index] : weekStart
                    ForEach(timeline.blocks) { block in
                        let laneWidth = (columnWidth - 2) / CGFloat(max(1, block.columnCount))
                        let top = M.y(forMinute: block.startMinute)
                        let height = max(M.minBlockHeight, M.y(forMinute: block.endMinute) - top) - 1
                        let view = TimelineBlockView(block: block, day: day, height: height,
                                                     showsTime: columnWidth >= Self.timeTextMinWidth,
                                                     compact: columnWidth < Self.timeTextMinWidth,
                                                     width: laneWidth - 1)
                        Button {
                            if let item = layout.items[index][block.id] { onOpenItem(item) }
                        } label: { view }
                            .buttonStyle(.plain)
                            .frame(width: max(0, laneWidth - 1), height: height)
                            .offset(x: CGFloat(index) * columnWidth + 1 + CGFloat(block.column) * laneWidth,
                                    y: top + 0.5)
                            .accessibilityLabel(AgendaFormat.weekdayName(day) + ", " + view.accessibilityText)
                            .accessibilityHint("Opens details")
                    }
                }
            }
        }
    }
}
