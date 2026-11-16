// ios/App/Stark/Stark/FullDayView.swift
import SwiftUI
import StarkKit

/// The full-screen Day (Fantastical's Day view): a "November 16, 2026" title (year in red) with
/// chevrons, the weekday in caps (blue on today), the day's all-day items as chips, then a
/// scrolling 24-hour `HourGrid` with the timed events and timed reminders as blocks and, on
/// today, the red now-line.
///
/// The rows come from `buildAgendaItems` then `agendaWithApple` over the day, as in
/// `FullQuarterView`, and `timelineLayout` places them. They are computed off the main actor,
/// debounced, and tagged with the day shown. Read-only: a tap on a block or chip opens the same
/// detail sheet as an agenda row (`onOpenItem`); tapping the weekday returns to the DayTicker on
/// this day (`onSelectDate`). Chevrons and horizontal swipes step one day.
struct FullDayView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(AppleOverlayModel.self) private var overlay
    @Environment(PlanCache.self) private var planCache
    /// Start of the day shown.
    @State private var day: Date
    @State private var snapshot: LayoutSnapshot?
    /// The "+N" of a full chip strip was tapped: every chip, scrolling. Reset on a new day.
    @State private var chipsExpanded = false
    let today: Date
    let onSelectDate: (Date) -> Void
    let onOpenItem: (AgendaItem) -> Void

    private typealias M = HourGridMetrics
    private static let calendar = Calendar(identifier: .gregorian)
    /// Chips shown before the strip scrolls.
    private static let visibleChips = 3

    init(today: Date, selectedDate: Date, onSelectDate: @escaping (Date) -> Void,
         onOpenItem: @escaping (AgendaItem) -> Void) {
        self.today = today
        self.onSelectDate = onSelectDate
        self.onOpenItem = onOpenItem
        _day = State(initialValue: Self.calendar.startOfDay(for: selectedDate))
    }

    private var isToday: Bool { Self.calendar.isDate(day, inSameDayAs: today) }

    var body: some View {
        let layout = snapshot?.day == day ? snapshot : nil
        VStack(spacing: 0) {
            header
            weekdayRow
            chipStrip(layout?.timeline.allDay ?? [], items: layout?.items ?? [:])
            Rectangle().fill(Colors.separator).frame(height: 0.5)
            ScrollViewReader { scroller in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        HourGrid(columnCount: 1, nowColumn: isToday ? 0 : nil) { width in
                            blocks(layout, width: width)
                        }
                        // Invisible hour anchors for the initial scroll.
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
                .onChange(of: day) { _, _ in
                    chipsExpanded = false
                    scrollToStart(scroller)
                }
            }
        }
        .background(Colors.card)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                    changeDay(by: dx < 0 ? 1 : -1)
                }
        )
        .task(id: day) {
            let range = Self.range(for: day)
            store.loadMonths(covering: range)
            await overlay.reload(for: .fullDay, display: range, today: today)
        }
        .onDisappear {
            let today = today
            Task { await overlay.reload(for: .fullDay, display: nil, today: today) }
        }
        // The day rolled over while Day showed the old today: follow it.
        .onChange(of: today) { oldToday, newToday in
            guard Self.calendar.isDate(day, inSameDayAs: oldToday) else { return }
            day = Self.calendar.startOfDay(for: newToday)
        }
        .task(id: layoutInputs) {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let inputs = layoutInputs
            let events = inputs.events, reminders = inputs.reminders, plans = inputs.plans
            let apple = inputs.apple, today = inputs.today, day = inputs.day
            let result = await Task.detached(priority: .userInitiated) {
                Self.computeLayout(events: events, reminders: reminders, plans: plans, apple: apple,
                                   day: day, today: today)
            }.value
            guard !Task.isCancelled else { return }
            snapshot = LayoutSnapshot(day: day, timeline: result.timeline, items: result.items)
        }
    }

    // MARK: - Data

    private struct LayoutInputs: Equatable {
        let day: Date
        let today: Date
        let events: [Event]
        let reminders: [Reminder]
        let plans: [PlanBlock]
        let apple: AppleSnapshot
    }

    private struct LayoutSnapshot {
        let day: Date
        let timeline: DayTimeline
        /// The agenda rows behind the blocks and chips, by id, for the detail sheet.
        let items: [String: AgendaItem]
    }

    private var layoutInputs: LayoutInputs {
        LayoutInputs(day: day, today: today, events: store.events, reminders: store.reminders,
                     plans: PlannerPlans.all(local: store.plans, apple: planCache.applePlans),
                     apple: overlay.snapshot)
    }

    /// The whole day, from its start to its last second.
    nonisolated static func range(for day: Date) -> ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: day)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return start...next.addingTimeInterval(-1)
    }

    nonisolated private static func computeLayout(
        events: [Event], reminders: [Reminder], plans: [PlanBlock], apple: AppleSnapshot,
        day: Date, today: Date
    ) -> (timeline: DayTimeline, items: [String: AgendaItem]) {
        let calendar = Calendar(identifier: .gregorian)
        let items = timelineAgendaItems(events: events, reminders: reminders, plans: plans, apple: apple,
                                        days: range(for: day), today: today, calendar: calendar)
        let timeline = timelineLayout(items: items, day: day, calendar: calendar)
        return (timeline, timeline.items)
    }

    /// Not a bare Int: `HourGrid`'s label `ForEach(0..<24, id: \.self)` would claim those ids, and
    /// its labels are laid out at the top (moved by `offset`), so `scrollTo(8)` went to midnight.
    private static func anchorID(_ hour: Int) -> String { "day-hour-\(hour)" }

    private func changeDay(by offset: Int) {
        day = Self.calendar.date(byAdding: .day, value: offset, to: day) ?? day
    }

    /// Today opens near now (an hour before, but not earlier than 7 AM); another day at 8 AM.
    private func scrollToStart(_ scroller: ScrollViewProxy) {
        let hour: Int
        if isToday {
            let now = Self.calendar.component(.hour, from: Date())
            hour = min(23, max(now - 1, 7))
        } else {
            hour = 8
        }
        // After the first layout pass, or the scroll view has no content size to scroll in yet.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            scroller.scrollTo(Self.anchorID(hour), anchor: .top)
        }
    }

    // MARK: - Header

    private var titleText: Text {
        let c = Self.calendar.dateComponents([.year], from: day)
        return Text(AgendaFormat.monthName(day) + " \(Self.calendar.component(.day, from: day)), ")
            .foregroundColor(Colors.text)
            + Text(String(c.year ?? 0)).foregroundColor(Colors.yearRed)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button { day = Self.calendar.startOfDay(for: today) } label: {
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
            .accessibilityHint("Goes to today")
            Spacer(minLength: 0)
            chevron("‹", label: "Previous day") { changeDay(by: -1) }
            chevron("›", label: "Next day") { changeDay(by: 1) }
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

    private var weekdayRow: some View {
        Button { onSelectDate(day) } label: {
            Text(AgendaFormat.weekdayName(day).uppercased())
                .font(Fonts.mono(15, weight: .semibold))
                .foregroundStyle(isToday ? Colors.accent : Colors.textSecondary)
                .padding(.leading, M.labelWidth)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityHint("Opens this day in the DayTicker")
    }

    // MARK: - All-day chips

    /// Up to `visibleChips` rows; with more, the last row is "+N", which opens the whole list
    /// (scrolling in a strip of the same height) instead of showing half a chip.
    @ViewBuilder
    private func chipStrip(_ chips: [TimelineChip], items: [String: AgendaItem]) -> some View {
        if !chips.isEmpty {
            let overflows = chips.count > Self.visibleChips
            let shown = overflows && !chipsExpanded ? Array(chips.prefix(Self.visibleChips - 1)) : chips
            let list = VStack(spacing: 3) {
                ForEach(shown) { chip in
                    Button { items[chip.id].map(onOpenItem) } label: { TimelineChipView(chip: chip) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(TimelineChipView.accessibilityText(chip))
                        .accessibilityHint("Opens details")
                }
                if overflows && !chipsExpanded {
                    Button { chipsExpanded = true } label: {
                        TimelineMoreChipView(count: chips.count - shown.count)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(chips.count - shown.count) more all-day items")
                    .accessibilityHint("Shows all")
                }
            }
            .padding(.leading, M.labelWidth)
            .padding(.trailing, Spacing.sm)
            .padding(.bottom, Spacing.xs)
            if overflows && chipsExpanded {
                ScrollView(.vertical) { list }
                    .frame(height: CGFloat(Self.visibleChips) * 25 + 12)
            } else {
                list
            }
        }
    }

    // MARK: - Blocks

    private func blocks(_ layout: LayoutSnapshot?, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout?.timeline.blocks ?? []) { block in
                let laneWidth = (width - Spacing.sm) / CGFloat(max(1, block.columnCount))
                let top = M.y(forMinute: block.startMinute)
                let height = max(M.minBlockHeight, M.y(forMinute: block.endMinute) - top) - 1
                let view = TimelineBlockView(block: block, day: day, height: height, width: laneWidth - 2)
                Button {
                    if let item = layout?.items[block.id] { onOpenItem(item) }
                } label: { view }
                    .buttonStyle(.plain)
                    .frame(width: max(0, laneWidth - 2), height: height)
                    .offset(x: CGFloat(block.column) * laneWidth + 1, y: top + 0.5)
                    .accessibilityLabel(view.accessibilityText)
                    .accessibilityHint("Opens details")
            }
        }
    }
}
