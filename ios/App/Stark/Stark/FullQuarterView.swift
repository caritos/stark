// ios/App/Stark/Stark/FullQuarterView.swift
import SwiftUI
import StarkKit

/// The full-screen Quarter (Fantastical's Quarter view): a "Nov 2026 – Jan 2027" title (years in
/// red) with chevrons, a SUN..SAT strip over a light-grey rule, and `QuarterGrid`'s 13 weeks
/// (from the Sunday on or before the 1st of the displayed month) as short day cells.
///
/// At this density nothing has text: all-day and multi-day events are thin colour bars across the
/// row (holiday calendars lilac), timed events are dots in their calendar colour and reminders are
/// small red squares. Whatever does not fit a cell is simply not drawn (no "N more"). The 1st of
/// each month is a grey pill ("Dec 1") and thicker grey seams separate the months.
///
/// The rows come from `buildAgendaItems` then `agendaWithApple` over the quarter's range, as in
/// `FullMonthView`, laid out by `gridLayout` with no capacity limit (the view decides what fits).
/// They are computed off the main actor, debounced, and tagged with the month shown.
///
/// A cell is one button: tapping it selects that day; `ContentView` then returns to the DayTicker
/// scrolled there. Chevrons and horizontal swipes page ONE month (the next 13 weeks), like
/// Fantastical.
struct FullQuarterView: View {
    @Environment(AppleOverlayModel.self) private var overlay
    /// Apple reminders' plan blocks (sidecar), applied like the agenda does.
    @Environment(PlanCache.self) private var planCache
    @State private var visibleMonth: YearMonth
    @State private var snapshot: LayoutSnapshot?
    let today: Date
    let onSelectDate: (Date) -> Void

    /// Height of the day-number band at the top of every cell.
    private static let numberBand: CGFloat = 22
    /// A bar's thickness and the distance from one bar lane to the next.
    private static let barHeight: CGFloat = 4
    private static let barPitch: CGFloat = 6
    /// A dot's (or reminder square's) size and the distance between neighbours and dot rows.
    private static let dotSize: CGFloat = 5
    private static let dotPitch: CGFloat = 7
    private static let minCellHeight: CGFloat = 56
    /// Width of the grey lines between months.
    private static let seamWidth: CGFloat = 2.5
    private static let gridTop = "quarterGridTop"
    private static let weekdayLabels = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    /// Large enough that `gridLayout` never hides anything; the view clips to what fits.
    private static let unlimited = 1_000

    init(today: Date, selectedDate: Date, onSelectDate: @escaping (Date) -> Void) {
        self.today = today
        self.onSelectDate = onSelectDate
        _visibleMonth = State(initialValue: YearMonth(date: selectedDate))
    }

    var body: some View {
        let days = QuarterGrid.days(startingAt: visibleMonth)
        // Only a layout made for the quarter on screen is drawn.
        let layout = snapshot?.month == visibleMonth ? snapshot : nil

        VStack(spacing: 0) {
            header
            weekdayStrip
            GeometryReader { proxy in
                // Fill the height (the last row may sit under the floating bar, as in
                // Fantastical); scroll when the rows would be shorter than the minimum.
                let cellHeight = max(Self.minCellHeight, floor(proxy.size.height / CGFloat(QuarterGrid.weekCount)))
                ScrollViewReader { scroller in
                    ScrollView(.vertical) {
                        grid(days: days, layout: layout, cellHeight: cellHeight, width: proxy.size.width)
                            .id(Self.gridTop)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .contentMargins(.bottom, FloatingBottomBar.clearance, for: .scrollContent)
                    // A new quarter starts at its first week, not at the old one's scroll offset.
                    .onChange(of: visibleMonth) { _, _ in scroller.scrollTo(Self.gridTop, anchor: .top) }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .background(Colors.card)
        // Horizontal swipe pages like the chevrons; vertical drags are left to the scroll view.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                    changeMonth(by: dx < 0 ? 1 : -1)
                }
        )
        // The Apple overlay must fetch the grid's range, or its days would silently show empty.
        .task(id: visibleMonth) {
            let range = QuarterGrid.range(for: visibleMonth)
            await overlay.reload(for: .fullQuarter, display: range, today: today)
        }
        // Stop widening the overlay's fetch to this grid once Quarter is gone.
        .onDisappear {
            let today = today
            Task { await overlay.reload(for: .fullQuarter, display: nil, today: today) }
        }
        // The day rolled over while Quarter started at the old today's month: follow it.
        .onChange(of: today) { oldToday, newToday in
            guard visibleMonth == YearMonth(date: oldToday) else { return }
            visibleMonth = YearMonth(date: newToday)
        }
        .task(id: layoutInputs) {
            // Debounce, as in `FullMonthView`: the detached work cannot be cancelled, so a burst
            // of chevron taps runs it once, for the last month.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let inputs = layoutInputs
            let events = inputs.events, reminders = inputs.reminders, plans = inputs.plans
            let apple = inputs.apple, today = inputs.today
            let (year, month0) = (inputs.month.year, inputs.month.month0)
            let result = await Task.detached(priority: .userInitiated) {
                Self.computeLayout(events: events, reminders: reminders, plans: plans, apple: apple,
                                   year: year, month0: month0, today: today)
            }.value
            guard !Task.isCancelled else { return }
            snapshot = LayoutSnapshot(month: inputs.month, weeks: result.weeks, counts: result.counts)
        }
    }

    // MARK: - Data

    private struct LayoutInputs: Equatable {
        let month: YearMonth
        let today: Date
        let events: [Event]
        let reminders: [Reminder]
        let plans: [PlanBlock]
        let apple: AppleSnapshot
    }

    private struct LayoutSnapshot {
        let month: YearMonth
        let weeks: [MonthWeek]
        /// Per ISO day, for VoiceOver: every row of the day, undrawn ones included.
        let counts: [String: DayDensity]
    }

    private var layoutInputs: LayoutInputs {
        LayoutInputs(month: visibleMonth, today: today,
                     events: [], reminders: [],
                     plans: planCache.applePlans,
                     apple: overlay.snapshot)
    }

    /// The agenda's own rows over the quarter (`FullMonthView`'s call shape), laid out by
    /// `gridLayout` with no capacity limit, plus per-day counts. Pure; runs off the main actor.
    nonisolated private static func computeLayout(
        events: [Event], reminders: [Reminder], plans: [PlanBlock], apple: AppleSnapshot,
        year: Int, month0: Int, today: Date
    ) -> (weeks: [MonthWeek], counts: [String: DayDensity]) {
        let month = YearMonth(year: year, month0: month0)
        let calendar = Calendar(identifier: .gregorian)
        let range = QuarterGrid.range(for: month)
        let base = buildAgendaItems(events: events, reminders: reminders, in: range, today: today)
        let items = agendaWithApple(local: base, snapshot: apple, plans: plans, range: range, today: today,
                                    reminders: reminders, calendar: calendar)
        var counts: [String: DayDensity] = [:]
        for item in items where range.contains(item.displayDate) {
            let c = calendar.dateComponents([.year, .month, .day], from: item.displayDate)
            guard let y = c.year, let m = c.month, let d = c.day else { continue }
            let iso = DateMath.isoDate(year: y, month0: m - 1, day: d)
            switch item.kind {
            case .event: counts[iso, default: .none].events += 1
            case .reminder: counts[iso, default: .none].tasks += 1
            }
        }
        let weeks = gridLayout(items: items, days: QuarterGrid.days(startingAt: month),
                               rowCapacity: unlimited, calendar: calendar)
        return (weeks, counts)
    }

    private func changeMonth(by offset: Int) {
        visibleMonth = YearMonth(year: visibleMonth.year, month0: visibleMonth.month0 + offset)
    }

    // MARK: - Header

    /// "Nov 2026 – Jan 2027", or "May – Jul 2026" when both ends share a year (Fantastical).
    private var titleText: Text {
        let (first, second) = QuarterGrid.title(for: visibleMonth)
        let a = first.split(separator: " ").map(String.init)
        let b = second.split(separator: " ").map(String.init)
        guard a.count == 2, b.count == 2 else { return Text("\(first) – \(second)").foregroundColor(Colors.text) }
        let firstPart = a[1] == b[1]
            ? Text(a[0] + " – ").foregroundColor(Colors.text)
            : Text(a[0] + " ").foregroundColor(Colors.text) + Text(a[1]).foregroundColor(Colors.yearRed)
                + Text(" – ").foregroundColor(Colors.text)
        return firstPart + Text(b[0] + " ").foregroundColor(Colors.text) + Text(b[1]).foregroundColor(Colors.yearRed)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button { visibleMonth = YearMonth(date: today) } label: {
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
            .accessibilityHint("Goes to the quarter starting this month")
            Spacer(minLength: 0)
            chevron("‹", label: "Previous month") { changeMonth(by: -1) }
            chevron("›", label: "Next month") { changeMonth(by: 1) }
        }
        .padding(.trailing, Spacing.sm)
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

    private var weekdayStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(Self.weekdayLabels[index])
                        .font(Fonts.mono(12, weight: .medium))
                        .foregroundStyle(Colors.text)
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
            }
            .accessibilityHidden(true)
            Rectangle().fill(Colors.quarterSeam).frame(height: Self.seamWidth)
        }
    }

    // MARK: - Grid

    private func grid(days: [GridDay], layout: LayoutSnapshot?, cellHeight: CGFloat, width: CGFloat) -> some View {
        let todayIso = DateMath.isoDate(from: today)
        let columnWidth = width / 7
        // Bar lanes that fit under the number band, leaving room for one row of dots.
        let lanes = max(1, Int(floor((cellHeight - Self.numberBand - Self.dotPitch - 2) / Self.barPitch)))
        return VStack(spacing: 0) {
            ForEach(0..<QuarterGrid.weekCount, id: \.self) { row in
                let week = layout.flatMap { row < $0.weeks.count ? $0.weeks[row] : nil }
                weekRow(Array(days[(row * 7)..<(row * 7 + 7)]), week: week, todayIso: todayIso,
                        counts: layout?.counts ?? [:], lanes: lanes,
                        columnWidth: columnWidth, cellHeight: cellHeight)
            }
        }
        .overlay { seams(days: days, columnWidth: columnWidth, cellHeight: cellHeight) }
    }

    private func weekRow(_ days: [GridDay], week: MonthWeek?, todayIso: String, counts: [String: DayDensity],
                         lanes: Int, columnWidth: CGFloat, cellHeight: CGFloat) -> some View {
        let bars = (week?.bars ?? []).filter { $0.lane < lanes }
        // Dots start under the lowest drawn bar of their own column.
        func used(_ col: Int) -> Int {
            bars.filter { $0.startColumn <= col && col <= $0.endColumn }.map { $0.lane + 1 }.max() ?? 0
        }
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { col, day in
                    dayCell(day, isToday: day.iso == todayIso, lines: week?.lines[col] ?? [],
                            dotsTop: Self.numberBand + CGFloat(used(col)) * Self.barPitch + (used(col) > 0 ? 2 : 0),
                            counts: counts[day.iso] ?? .none, width: columnWidth, height: cellHeight)
                }
            }
            ForEach(bars, id: \.id) { bar in
                barView(bar, columnWidth: columnWidth)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: cellHeight)
        .clipped()
    }

    private func barView(_ bar: MonthBar, columnWidth: CGFloat) -> some View {
        let fill = bar.isHoliday ? Colors.holidayBar : (bar.colorRGB.map { Color(hex: $0) } ?? Colors.eventDot)
        let inset: CGFloat = 4
        let squareLeft = bar.continuesBefore, squareRight = bar.continuesAfter
        let width = CGFloat(bar.endColumn - bar.startColumn + 1) * columnWidth
            - (squareLeft ? 0 : inset) - (squareRight ? 0 : inset)
        let radius = Self.barHeight / 2
        return UnevenRoundedRectangle(
            topLeadingRadius: squareLeft ? 0 : radius, bottomLeadingRadius: squareLeft ? 0 : radius,
            bottomTrailingRadius: squareRight ? 0 : radius, topTrailingRadius: squareRight ? 0 : radius)
            .fill(fill)
            .frame(width: max(0, width), height: Self.barHeight)
            .offset(x: CGFloat(bar.startColumn) * columnWidth + (squareLeft ? 0 : inset),
                    y: Self.numberBand + CGFloat(bar.lane) * Self.barPitch)
    }

    private func dayCell(_ day: GridDay, isToday: Bool, lines: [MonthLine], dotsTop: CGFloat,
                         counts: DayDensity, width: CGFloat, height: CGFloat) -> some View {
        Button {
            onSelectDate(day.date)
        } label: {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(isToday ? Colors.todayCell : Colors.card)
                dayNumber(day, isToday: isToday)
                    .frame(width: width, height: Self.numberBand, alignment: .trailing)
                dots(lines, width: width, height: height - dotsTop)
                    .offset(y: dotsTop)
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .overlay(alignment: .trailing) { Rectangle().fill(Colors.separator).frame(width: 0.5) }
            .overlay(alignment: .top) { Rectangle().fill(Colors.separator).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(counts.accessibilityLabel(title: AgendaFormat.monthDay(day.date), isToday: isToday))
        .accessibilityHint("Opens this day")
    }

    /// The day's timed events (calendar-coloured dots) then reminders (small red squares), in
    /// rows from the leading edge; those that do not fit the cell are left out.
    private func dots(_ lines: [MonthLine], width: CGFloat, height: CGFloat) -> some View {
        let perRow = max(1, Int(floor((width - 6) / Self.dotPitch)))
        let rows = max(0, Int(floor((height - 2) / Self.dotPitch)))
        let shown = Array(lines.prefix(perRow * rows))
        return ZStack(alignment: .topLeading) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, line in
                dot(line)
                    .offset(x: 4 + CGFloat(index % perRow) * Self.dotPitch,
                            y: CGFloat(index / perRow) * Self.dotPitch)
            }
        }
        .frame(width: width, height: max(0, height), alignment: .topLeading)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func dot(_ line: MonthLine) -> some View {
        switch line.kind {
        case .timed(let rgb):
            Circle().fill(rgb.map { Color(hex: $0) } ?? Colors.eventDot)
                .frame(width: Self.dotSize, height: Self.dotSize)
        case .reminder(let isCompleted, _):
            RoundedRectangle(cornerRadius: 1)
                .strokeBorder(Colors.reminderBox, lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 1).fill(isCompleted ? Colors.reminderBox : Color.clear))
                .frame(width: Self.dotSize, height: Self.dotSize)
        }
    }

    @ViewBuilder
    private func dayNumber(_ day: GridDay, isToday: Bool) -> some View {
        let pill = QuarterGrid.monthStartLabel(for: day)
        // Days before the displayed month's 1st (the first row's lead-in) read grey.
        let leadIn = day.year * 12 + day.month0 < visibleMonth.year * 12 + visibleMonth.month0
        Group {
            if isToday {
                Text(pill ?? "\(day.day)")
                    .font(Fonts.mono(12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 20, minHeight: 18)
                    .background(Capsule().fill(Colors.accent))
            } else if let pill {
                // The first of a month is a grey pill ("Dec 1"), as in Fantastical.
                Text(pill)
                    .font(Fonts.mono(11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 5)
                    .frame(minHeight: 16)
                    .background(Capsule().fill(Colors.textSecondary))
            } else {
                Text("\(day.day)")
                    .font(Fonts.mono(12, weight: .semibold))
                    .foregroundStyle(leadIn ? Colors.textSecondary : Colors.text)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.trailing, 4)
        .padding(.top, 2)
    }

    /// The thicker grey lines along every month boundary (`QuarterGrid.seam`): over a cell's top
    /// edge where the cell above is another month, and its leading edge where the cell to the
    /// left is.
    private func seams(days: [GridDay], columnWidth: CGFloat, cellHeight: CGFloat) -> some View {
        Path { p in
            for index in days.indices {
                let seam = QuarterGrid.seam(at: index, in: days)
                let x = CGFloat(index % 7) * columnWidth, y = CGFloat(index / 7) * cellHeight
                if seam.top {
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x + columnWidth, y: y))
                }
                if seam.leading {
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x, y: y + cellHeight))
                }
            }
        }
        .stroke(Colors.quarterSeam, style: StrokeStyle(lineWidth: Self.seamWidth, lineCap: .square))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
