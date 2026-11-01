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
    private static let hourHeight: CGFloat = 60
    private static let gutter: CGFloat = 60
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
    private var dayEnd: Date { cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400) }
    private var slotCount: Int { Int((dayEnd.timeIntervalSince(dayStart) / 3600).rounded()) }
    private var contentHeight: CGFloat { CGFloat(slotCount) * Self.hourHeight }
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
                if !history.allDayEvents.isEmpty { banner(history.allDayEvents) }
                Rectangle().fill(Colors.separator).frame(height: 1)
                timeline(history)
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

    // MARK: Banner

    private func banner(_ items: [AgendaItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(items) { item in
                    Text(item.title)
                        .font(Fonts.mono(11))
                        .foregroundStyle(Colors.text)
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(Colors.eventDot.opacity(0.35))
                        .overlay(alignment: .leading) { Rectangle().fill(Colors.eventDot).frame(width: 3) }
                        .accessibilityLabel("All day: \(item.title)")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: Timeline

    private func y(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 3600) * Self.hourHeight
    }

    private func timeline(_ h: DayHistory) -> some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    content(h, width: outer.size.width)
                }
                .onAppear { scroll(proxy, h) }
                .onChange(of: day) { _, _ in scroll(proxy, history) }
            }
        }
    }

    /// Opens an hour above the first block of the day, else at 07:00.
    private func scroll(_ proxy: ScrollViewProxy, _ h: DayHistory) {
        let first = (h.done.map(\.block.start) + h.open.map(\.block.start)).min()
        let hour = first.map { max(Int($0.timeIntervalSince(dayStart) / 3600) - 1, 0) } ?? 7
        let target = min(hour, max(slotCount - 1, 0))
        DispatchQueue.main.async { proxy.scrollTo("hour-\(target)", anchor: .top) }
    }

    private func content(_ h: DayHistory, width: CGFloat) -> some View {
        let laneWidth = max(width - Self.gutter - Spacing.sm, 100)
        let eventWidth = (laneWidth * 0.38).rounded()
        let taskX = Self.gutter + eventWidth + Spacing.xs
        let taskWidth = laneWidth - eventWidth - Spacing.xs
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<slotCount, id: \.self) { hourRow($0).id("hour-\($0)") }
            }
            .frame(width: width)
            ForEach(h.events) { item in
                eventBlock(item)
                    .frame(width: eventWidth, height: eventHeight(item))
                    .offset(x: Self.gutter, y: y(for: max(item.occurrence, dayStart)))
            }
            ForEach(h.done) { done in
                doneBlock(done)
                    .frame(width: taskWidth, height: blockHeight(done.block))
                    .offset(x: taskX, y: y(for: done.block.start))
            }
            ForEach(h.open) { open in
                openBlock(open)
                    .frame(width: taskWidth, height: blockHeight(open.block))
                    .offset(x: taskX, y: y(for: open.block.start))
            }
        }
        .frame(width: width, height: contentHeight, alignment: .topLeading)
    }

    private func hourRow(_ index: Int) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Colors.separator).frame(height: 1).padding(.leading, Self.gutter - Spacing.xs)
            Text(AgendaFormat.time(dayStart.addingTimeInterval(TimeInterval(index * 3600))))
                .font(Fonts.mono(10))
                .foregroundStyle(Colors.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: Self.gutter - Spacing.sm, alignment: .trailing)
                .offset(y: -6)
                .accessibilityHidden(true)
        }
        .frame(height: Self.hourHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func blockHeight(_ block: PlanBlock) -> CGFloat {
        max(CGFloat(block.minutes) / 60 * Self.hourHeight - 1, 1)
    }

    private func eventHeight(_ item: AgendaItem) -> CGFloat {
        guard case .event(let event) = item.kind else { return 20 }
        let start = max(item.occurrence, dayStart)
        let length = event.end.map { $0.timeIntervalSince(event.start) } ?? 0
        let end = min(item.occurrence.addingTimeInterval(length), dayEnd)
        return max(CGFloat(end.timeIntervalSince(start) / 3600) * Self.hourHeight, 20)
    }

    private func eventBlock(_ item: AgendaItem) -> some View {
        Text(item.title)
            .font(Fonts.mono(10))
            .foregroundStyle(Colors.text.opacity(0.8))
            .lineLimit(2)
            .padding(.horizontal, Spacing.xs).padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Colors.eventDot.opacity(0.3))
            .overlay(alignment: .leading) { Rectangle().fill(Colors.eventDot.opacity(0.8)).frame(width: 2) }
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Event: \(item.title), \(AgendaFormat.time(item.occurrence))")
    }

    private func range(_ block: PlanBlock) -> String {
        "\(AgendaFormat.time(block.start))–\(AgendaFormat.time(block.end))"
    }

    private func doneBlock(_ done: DayPlanModel.DoneBlock) -> some View {
        let block = done.block
        let title = Text(done.title).font(Fonts.mono(11))
            .strikethrough(true, color: Colors.textSecondary)
            .foregroundStyle(Colors.textSecondary)
        return HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Colors.accent.opacity(0.8))
                .padding(.top, 3)
            if block.minutes < 30 {
                title.lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(range(block)).font(Fonts.mono(9)).foregroundStyle(Colors.textSecondary.opacity(0.8))
                    title.lineLimit(block.minutes >= 45 ? 2 : 1)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Colors.accent.opacity(0.12))
        .overlay { Rectangle().strokeBorder(Colors.accent.opacity(0.4), lineWidth: 1) }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("done: \(done.title), \(range(block))")
    }

    private func openBlock(_ open: DayHistory.OpenBlock) -> some View {
        let block = open.block
        let label = isToday ? "OPEN" : "MISSED"
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: Spacing.xs) {
                Text(label).font(Fonts.mono(8, weight: .semibold)).tracking(1).foregroundStyle(Colors.accent)
                if block.minutes >= 30 {
                    Text(range(block)).font(Fonts.mono(9)).foregroundStyle(Colors.textSecondary)
                }
            }
            Text(open.title).font(Fonts.mono(11)).foregroundStyle(Colors.text)
                .lineLimit(block.minutes >= 45 ? 2 : 1)
        }
        .padding(.horizontal, Spacing.xs).padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay { Rectangle().strokeBorder(Colors.accent, lineWidth: 1) }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.lowercased()): \(open.title), \(range(block))")
    }
}
