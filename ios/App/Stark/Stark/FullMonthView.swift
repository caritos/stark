// ios/App/Stark/Stark/FullMonthView.swift
import SwiftUI
import StarkKit

/// The full-screen Month (Fantastical's Month view): a large month title with chevrons, a
/// SUN..SAT strip over a blue rule, and the 6-week `MonthGrid` as tall day cells that fill the
/// height down to the floating bar.
///
/// Each week row draws `monthLayout`'s result and nothing else: all-day and multi-day events as
/// bars across the row (holiday calendars as lilac chips), then per day the timed events (dot +
/// title) and reminders (checkbox + title), and "N more…" when the day has more than fits. The
/// rows come from `buildAgendaItems` then `agendaWithApple` over the grid's range, the same call
/// shape as `gridDensity`, so Month never disagrees with the agenda. They are computed off the
/// main actor, debounced, and tagged with the month (paging never shows the previous month's
/// items on the new month's days).
///
/// A cell is one button: tapping it (or its "N more…") selects that day; `ContentView` then
/// returns to the DayTicker scrolled there. Horizontal swipes page months like the chevrons.
struct FullMonthView: View {
    @Environment(AppleOverlayModel.self) private var overlay
    /// Apple reminders' plan blocks (sidecar), applied like the agenda does.
    @Environment(PlanCache.self) private var planCache
    @State private var visibleMonth: YearMonth
    @State private var snapshot: LayoutSnapshot?
    /// Rows of 18 pt that fit under a cell's number band; follows the grid's height.
    @State private var rowCapacity = 0
    let today: Date
    let onSelectDate: (Date) -> Void

    /// Height of the day-number band at the top of every cell.
    private static let numberBand: CGFloat = 24
    /// Height of one bar or line row.
    private static let rowHeight: CGFloat = 18
    private static let minCellHeight: CGFloat = 80
    private static let weekdayLabels = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    init(today: Date, selectedDate: Date, onSelectDate: @escaping (Date) -> Void) {
        self.today = today
        self.onSelectDate = onSelectDate
        _visibleMonth = State(initialValue: YearMonth(date: selectedDate))
    }

    var body: some View {
        let days = MonthGrid.days(for: visibleMonth)
        // Only a layout made for the month on screen (and the current capacity) is drawn.
        let layout = snapshot?.month == visibleMonth && snapshot?.capacity == rowCapacity ? snapshot : nil

        VStack(spacing: 0) {
            header
            weekdayStrip
            GeometryReader { proxy in
                let available = proxy.size.height - FloatingBottomBar.clearance
                let cellHeight = max(Self.minCellHeight, floor(available / 6))
                ScrollView(.vertical) {
                    grid(days: days, layout: layout, cellHeight: cellHeight, width: proxy.size.width)
                }
                .scrollBounceBehavior(.basedOnSize)
                .contentMargins(.bottom, FloatingBottomBar.clearance, for: .scrollContent)
                .onAppear { updateCapacity(cellHeight) }
                .onChange(of: cellHeight) { _, h in updateCapacity(h) }
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
            let range = MonthGrid.range(for: visibleMonth)
            await overlay.reload(for: .fullMonth, display: range, today: today)
        }
        // Stop widening the overlay's fetch to this grid once Month is gone.
        .onDisappear {
            let today = today
            Task { await overlay.reload(for: .fullMonth, display: nil, today: today) }
        }
        // The day rolled over while Month showed the old today's month: show the new one.
        .onChange(of: today) { oldToday, newToday in
            guard visibleMonth == YearMonth(date: oldToday) else { return }
            visibleMonth = YearMonth(date: newToday)
        }
        .task(id: layoutInputs) {
            // Debounce, as in `YearView`: the detached work cannot be cancelled, so a burst of
            // chevron taps runs it once, for the last month.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let inputs = layoutInputs
            guard inputs.capacity > 0 else { return }
            let events = inputs.events, reminders = inputs.reminders, plans = inputs.plans
            let apple = inputs.apple, today = inputs.today, capacity = inputs.capacity
            let (year, month0) = (inputs.month.year, inputs.month.month0)
            let result = await Task.detached(priority: .userInitiated) {
                Self.computeLayout(events: events, reminders: reminders, plans: plans, apple: apple,
                                   year: year, month0: month0, today: today, capacity: capacity)
            }.value
            guard !Task.isCancelled else { return }
            snapshot = LayoutSnapshot(month: inputs.month, capacity: capacity,
                                      weeks: result.weeks, counts: result.counts)
        }
    }

    // MARK: - Data

    private struct LayoutInputs: Equatable {
        let month: YearMonth
        let today: Date
        let capacity: Int
        let events: [Event]
        let reminders: [Reminder]
        let plans: [PlanBlock]
        let apple: AppleSnapshot
    }

    private struct LayoutSnapshot {
        let month: YearMonth
        let capacity: Int
        let weeks: [MonthWeek]
        /// Per ISO day, for VoiceOver: every row of the day, hidden ones included.
        let counts: [String: DayDensity]
    }

    private var layoutInputs: LayoutInputs {
        LayoutInputs(month: visibleMonth, today: today, capacity: rowCapacity,
                     events: [], reminders: [],
                     plans: planCache.applePlans,
                     apple: overlay.snapshot)
    }

    /// The agenda's own rows over the grid (`gridDensity`'s call shape), laid out by `monthLayout`,
    /// plus per-day counts. Pure; runs off the main actor.
    nonisolated private static func computeLayout(
        events: [Event], reminders: [Reminder], plans: [PlanBlock], apple: AppleSnapshot,
        year: Int, month0: Int, today: Date, capacity: Int
    ) -> (weeks: [MonthWeek], counts: [String: DayDensity]) {
        let month = YearMonth(year: year, month0: month0)
        let calendar = Calendar(identifier: .gregorian)
        let range = MonthGrid.range(for: month)
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
        let weeks = monthLayout(items: items, month: month, rowCapacity: capacity, calendar: calendar)
        return (weeks, counts)
    }

    private func updateCapacity(_ cellHeight: CGFloat) {
        let capacity = max(1, Int(floor((cellHeight - Self.numberBand) / Self.rowHeight)))
        if capacity != rowCapacity { rowCapacity = capacity }
    }

    private func changeMonth(by offset: Int) {
        visibleMonth = YearMonth(year: visibleMonth.year, month0: visibleMonth.month0 + offset)
    }

    // MARK: - Header

    private var header: some View {
        let first = DateMath.date(from: DateMath.isoDate(year: visibleMonth.year, month0: visibleMonth.month0, day: 1))
        let parts = AgendaFormat.monthYear(first).split(separator: " ", maxSplits: 1).map(String.init)
        return HStack(spacing: 0) {
            Button { visibleMonth = YearMonth(date: today) } label: {
                (Text((parts.first ?? "") + " ").foregroundColor(Colors.text)
                    + Text(parts.count > 1 ? parts[1] : "").foregroundColor(Colors.yearRed))
                    .font(Fonts.mono(30, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.leading, Spacing.md)
                    .padding(.trailing, Spacing.md)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint("Goes to this month")
            Spacer()
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
            Rectangle().fill(Colors.monthOutline).frame(height: 2)
        }
    }

    // MARK: - Grid

    private func grid(days: [GridDay], layout: LayoutSnapshot?, cellHeight: CGFloat, width: CGFloat) -> some View {
        let todayIso = DateMath.isoDate(from: today)
        let columnWidth = width / 7
        let rows = days.count / 7
        return VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                let week = layout.flatMap { row < $0.weeks.count ? $0.weeks[row] : nil }
                weekRow(Array(days[(row * 7)..<(row * 7 + 7)]), week: week, todayIso: todayIso,
                        counts: layout?.counts ?? [:], columnWidth: columnWidth, cellHeight: cellHeight)
            }
        }
        .overlay { monthOutline(days: days, columnWidth: columnWidth, cellHeight: cellHeight) }
    }

    private func weekRow(_ days: [GridDay], week: MonthWeek?, todayIso: String, counts: [String: DayDensity],
                         columnWidth: CGFloat, cellHeight: CGFloat) -> some View {
        let capacity = rowCapacity
        let overflowing = (0..<7).map { (week?.overflow[$0] ?? 0) > 0 }
        let bars = week?.bars ?? []
        // Lanes in use above a day's lines. On an overflowing day, bars in the label's row (or
        // below) are hidden there, exactly as `monthLayout` counted them.
        func used(_ col: Int) -> Int {
            bars.filter { $0.startColumn <= col && col <= $0.endColumn
                && ($0.lane < capacity - 1 || !overflowing[col]) }
                .map { $0.lane + 1 }.max() ?? 0
        }
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { col, day in
                    dayCell(day, isToday: day.iso == todayIso, lines: week?.lines[col] ?? [],
                            linesTop: Self.numberBand + CGFloat(used(col)) * Self.rowHeight,
                            overflow: week?.overflow[col] ?? 0, capacity: capacity,
                            counts: counts[day.iso] ?? .none, width: columnWidth, height: cellHeight)
                }
            }
            ForEach(bars, id: \.id) { bar in
                ForEach(Array(segments(of: bar, overflowing: overflowing, capacity: capacity).enumerated()), id: \.offset) { _, seg in
                    barView(bar, segment: seg, columnWidth: columnWidth)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: cellHeight)
        .clipped()
    }

    /// The column runs a bar is drawn over: all of it, except that a bar in the "N more…" row is
    /// left out of the days where that label sits.
    private struct BarSegment { let start: Int; let end: Int; let squareLeft: Bool; let squareRight: Bool; let showsTitle: Bool }

    private func segments(of bar: MonthBar, overflowing: [Bool], capacity: Int) -> [BarSegment] {
        let drawable = (bar.startColumn...bar.endColumn).map { bar.lane < capacity - 1 || !overflowing[$0] }
        var result: [BarSegment] = []
        var col = bar.startColumn
        while col <= bar.endColumn {
            guard drawable[col - bar.startColumn] else { col += 1; continue }
            var end = col
            while end + 1 <= bar.endColumn, drawable[end + 1 - bar.startColumn] { end += 1 }
            result.append(BarSegment(
                start: col, end: end,
                squareLeft: col > bar.startColumn || bar.continuesBefore,
                squareRight: end < bar.endColumn || bar.continuesAfter,
                showsTitle: result.isEmpty))
            col = end + 1
        }
        return result
    }

    private func barView(_ bar: MonthBar, segment: BarSegment, columnWidth: CGFloat) -> some View {
        let tint = bar.colorRGB.map { Color(hex: $0) } ?? Colors.eventDot
        let fill = bar.isHoliday ? Colors.holidayChip : tint.opacity(0.2)
        let textColor = bar.isHoliday ? Colors.holidayText : tint
        let inset: CGFloat = 2
        let width = CGFloat(segment.end - segment.start + 1) * columnWidth
            - (segment.squareLeft ? 0 : inset) - (segment.squareRight ? 0 : inset)
        let radius: CGFloat = 3
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: segment.squareLeft ? 0 : radius, bottomLeadingRadius: segment.squareLeft ? 0 : radius,
            bottomTrailingRadius: segment.squareRight ? 0 : radius, topTrailingRadius: segment.squareRight ? 0 : radius)
        return ZStack(alignment: .leading) {
            shape.fill(fill)
            if segment.showsTitle {
                clippedText(bar.title, color: textColor, weight: .medium)
                    .padding(.horizontal, 3)
            }
        }
        .frame(width: max(0, width), height: Self.rowHeight - 2)
        .clipShape(shape)
        .offset(x: CGFloat(segment.start) * columnWidth + (segment.squareLeft ? 0 : inset),
                y: Self.numberBand + CGFloat(bar.lane) * Self.rowHeight + 1)
    }

    /// One line of cell text, cut off hard at the cell's edge as Fantastical does (no ellipsis:
    /// the cells are too narrow to spend three characters on one).
    private func clippedText(_ text: String, color: Color, weight: Font.Weight = .regular, strike: Bool = false) -> some View {
        Text(text)
            .font(Fonts.mono(12, weight: weight))
            .strikethrough(strike)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            // minWidth 0: take the offered width (not the text's), so a long title starts at the
            // leading edge and is cut on the trailing one.
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
    }

    private func dayCell(_ day: GridDay, isToday: Bool, lines: [MonthLine], linesTop: CGFloat, overflow: Int,
                         capacity: Int, counts: DayDensity, width: CGFloat, height: CGFloat) -> some View {
        Button {
            onSelectDate(day.date)
        } label: {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(isToday ? Colors.todayCell : (day.isInMonth ? Colors.card : Colors.background))
                dayNumber(day, isToday: isToday)
                    .frame(width: width, height: Self.numberBand, alignment: .trailing)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines, id: \.id) { line in
                        lineView(line).frame(height: Self.rowHeight)
                    }
                }
                .frame(width: width, alignment: .leading)
                .offset(y: linesTop)
                if overflow > 0 {
                    clippedText("\(overflow) more…", color: Colors.textSecondary)
                        .padding(.horizontal, 3)
                        .frame(width: width, height: Self.rowHeight, alignment: .leading)
                        .offset(y: Self.numberBand + CGFloat(max(capacity - 1, 0)) * Self.rowHeight)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .overlay(alignment: .trailing) { Rectangle().fill(Colors.separator).frame(width: 0.5) }
            .overlay(alignment: .top) { Rectangle().fill(Colors.separator).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(counts.accessibilityLabel(
            title: day.isInMonth ? "\(day.day)" : AgendaFormat.monthDay(day.date), isToday: isToday))
        .accessibilityHint("Opens this day")
    }

    @ViewBuilder
    private func dayNumber(_ day: GridDay, isToday: Bool) -> some View {
        let isFirst = day.day == 1
        let text = isFirst ? AgendaFormat.monthDay(day.date) : "\(day.day)"
        Group {
            if isToday {
                Text(text)
                    .font(Fonts.mono(13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22, minHeight: 20)
                    .background(Capsule().fill(Colors.accent))
            } else if isFirst {
                // The first of a month is a grey pill ("Nov 1"), as in Fantastical.
                Text(text)
                    .font(Fonts.mono(12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 18)
                    .background(Capsule().fill(Colors.textSecondary))
            } else {
                Text(text)
                    .font(Fonts.mono(13, weight: .semibold))
                    .foregroundStyle(day.isInMonth ? Colors.text : Colors.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.trailing, 4)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func lineView(_ line: MonthLine) -> some View {
        switch line.kind {
        case .timed(let rgb):
            HStack(spacing: 3) {
                Circle().fill(rgb.map { Color(hex: $0) } ?? Colors.eventDot).frame(width: 6, height: 6)
                clippedText(line.title, color: Colors.text)
            }
            .padding(.leading, 3)
        case .reminder(let isCompleted, let isRecurring):
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Colors.reminderBox, lineWidth: 1.2)
                    .frame(width: 9, height: 9)
                    .overlay {
                        if isCompleted {
                            Image(systemName: "checkmark").font(.system(size: 6, weight: .bold))
                                .foregroundStyle(Colors.reminderBox)
                        }
                    }
                clippedText(line.title, color: isCompleted ? Colors.textSecondary : Colors.text, strike: isCompleted)
                if isRecurring {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8))
                        .foregroundStyle(Colors.textSecondary)
                        .padding(.trailing, 2)
                }
            }
            .padding(.leading, 3)
        }
    }

    /// One 2 pt outline around the displayed month's days (a staircase polygon: the in-month
    /// cells are one contiguous run of the grid).
    private func monthOutline(days: [GridDay], columnWidth: CGFloat, cellHeight: CGFloat) -> some View {
        let first = days.firstIndex { $0.isInMonth } ?? 0
        let last = days.lastIndex { $0.isInMonth } ?? 0
        let (ra, ca) = (CGFloat(first / 7), CGFloat(first % 7))
        let (rb, cb) = (CGFloat(last / 7), CGFloat(last % 7))
        let w = columnWidth, h = cellHeight
        return Path { p in
            let inset: CGFloat = 1
            let maxX = 7 * w - inset
            p.move(to: CGPoint(x: ca * w + inset, y: ra * h + inset))
            p.addLine(to: CGPoint(x: maxX, y: ra * h + inset))
            p.addLine(to: CGPoint(x: maxX, y: rb * h))
            let endX = cb == 6 ? maxX : (cb + 1) * w
            p.addLine(to: CGPoint(x: endX, y: rb * h))
            p.addLine(to: CGPoint(x: endX, y: (rb + 1) * h - inset))
            p.addLine(to: CGPoint(x: inset, y: (rb + 1) * h - inset))
            p.addLine(to: CGPoint(x: inset, y: (ra + 1) * h))
            p.addLine(to: CGPoint(x: ca * w + inset, y: (ra + 1) * h))
            p.closeSubpath()
        }
        .stroke(Colors.monthOutline, style: StrokeStyle(lineWidth: 2, lineJoin: .miter))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
