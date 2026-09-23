// ios/App/Stark/Stark/AgendaView.swift
import SwiftUI
import StarkKit

/// A request to scroll the agenda to a date. A fresh `token` per request makes tapping the
/// same date twice a *different* value, so `onChange` fires (and scrolls) again.
struct ScrollRequest: Equatable {
    let date: Date
    let token = UUID()
}

/// Day-grouped agenda. Items come from `buildAgendaItems` and are grouped by `groupAgendaByDay`,
/// which gives **every calendar day** of the display window a section (header) whether or not it
/// has items, so the month grid can scroll to any tapped day. An empty day shows just its header;
/// an empty today also keeps a "No events" row.
///
/// The display window is `AgendaWindow.range(around: anchor)`. `anchor` is today until the user
/// taps a grid day outside the window, when `ContentView` re-centres it on that day. Overdue
/// logic stays anchored on the *real* today, so when the window has been re-centred away from
/// today, today's section is not in the range and overdue-pinned reminders (whose `displayDate`
/// is today) are simply not shown until the window returns to today. That is expected.
struct AgendaView: View {
    @EnvironmentObject private var store: PlannerStore
    @EnvironmentObject private var pending: PendingCompletions
    /// The real today, owned by `ContentView` (which advances it when the calendar day changes) so
    /// this view re-renders on the new day instead of reading `Date()` once and going stale.
    let today: Date
    let anchor: Date
    let scrollRequest: ScrollRequest?
    let onSelect: (AgendaItem) -> Void
    /// Called (debounced, and suppressed for 300ms after a tap-driven `scrollRequest`) with the
    /// day whose row is at the top of the list, as the user scrolls. Defaulted so existing call
    /// sites compile unchanged; `ContentView` passes a real closure to drive calendar paging
    /// (issue #101). Never called as a side effect of `scrollRequest`'s own programmatic scroll —
    /// see `scrollSuppressUntil`. `var`, not `let`: a `let` with an inline default is excluded
    /// from the synthesized memberwise init entirely, so the parameter would not exist.
    var onDayInView: (Date) -> Void = { _ in }

    /// False until the list has been scrolled to today once real data has arrived. The display
    /// window includes the previous 14 days, and the store loads asynchronously after the first
    /// render, so the initial scroll has to be repeated when the first items arrive. (Every day
    /// has a section now, so the day list itself no longer changes when data loads.)
    @State private var hasSettled = false
    /// Ids of the rows a list cell is currently displayed for (`onAppear`/`onDisappear`). Used
    /// instead of `.scrollPosition(id:)`, which never reports a position on a `List` (issue #101).
    @State private var displayedRowIDs: Set<String> = []
    /// While `Date()` is before this, scroll-tracking reports are ignored — covers a
    /// tap-driven `scrollRequest`'s own (instant, unanimated) `proxy.scrollTo` jump, so it can
    /// never be mistaken for a user scroll and cause an unwanted grid page (issue #96: a tap on
    /// a neighbouring-month day must never page the month grid, even though it does scroll the
    /// agenda there).
    @State private var scrollSuppressUntil = Date.distantPast

    private static let calendar = Calendar(identifier: .gregorian)

    private enum ListRow: Identifiable {
        /// `compact` is true for a day with nothing under it (other than today, which keeps its
        /// "No events" row): List's minimum row height would otherwise pad the bare header.
        case header(day: Date, compact: Bool)
        case empty(day: Date, divider: Bool)
        case item(AgendaItem, endsSection: Bool, divider: Bool)
        /// Blank space after the last section, one viewport tall, so even the final days'
        /// headers can be scrolled to the top of the list.
        case tail

        var id: String {
            switch self {
            case .header(let day, _): return AgendaView.headerID(day)
            case .empty(let day, _): return "empty-\(Int(day.timeIntervalSince1970))"
            case .item(let item, _, _): return item.id
            case .tail: return "tail"
            }
        }
    }

    var body: some View {
        let now = today
        let todayStart = Self.calendar.startOfDay(for: now)
        let sections = makeSections(now: now)
        let rows = makeRows(sections, todayStart: todayStart)
        let itemCount = sections.reduce(0) { $0 + $1.items.count }
        let rowDayLookup = makeRowDayLookup(sections, todayStart: todayStart)

        GeometryReader { geometry in
            ScrollViewReader { proxy in
                List {
                    ForEach(rows) { row in
                        Group {
                        switch row {
                        case .header(let day, let compact):
                            headerRow(day: day, todayStart: todayStart, compact: compact)
                        case .empty(_, let divider):
                            Text("No events")
                                .font(.subheadline)
                                .foregroundStyle(Colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.xs)
                                .sectionEnd(divider: divider)
                                .frame(minHeight: Self.rowMinHeight)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Colors.background)
                                .listRowInsets(EdgeInsets())
                        case .item(let item, let endsSection, let divider):
                            itemRow(item, endsSection: endsSection, divider: divider)
                        case .tail:
                            Color.clear
                                .frame(height: geometry.size.height)
                                .allowsHitTesting(false)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Colors.background)
                                .listRowInsets(EdgeInsets())
                        }
                        }
                        .onAppear { displayedRowIDs.insert(row.id) }
                        .onDisappear { displayedRowIDs.remove(row.id) }
                    }
                }
                .listStyle(.plain)
                // Lets a bare empty-day header be as short as its content; every other row
                // restores the old minimum via `rowMinHeight`.
                .environment(\.defaultMinListRowHeight, 0)
                .listRowSeparatorTint(Colors.separator)
                .scrollContentBackground(.hidden)
                .background(Colors.background)
                .onAppear {
                    scrollToToday(proxy, todayStart: todayStart)
                }
                // Never drop a still-pending completion when the agenda goes away.
                .onDisappear { pending.flush() }
                .onChange(of: itemCount) { _, _ in
                    guard !hasSettled else { return }
                    scrollToToday(proxy, todayStart: todayStart)
                    // Until the first real items arrive there is nothing more to wait for
                    // yet; keep re-anchoring on today.
                    hasSettled = itemCount > 0
                }
                // Declared after the item-count handler on purpose: when both fire in one
                // update, this (the later, deferred scroll) wins.
                .onChange(of: scrollRequest) { _, request in
                    guard let request else { return }
                    hasSettled = true
                    scrollSuppressUntil = Date().addingTimeInterval(0.3)
                    let target = Self.calendar.startOfDay(for: request.date)
                    // The exact day's header; falls back to the first section after it
                    // (else the last) if it is somehow missing from the window.
                    guard let section = sections.first(where: { $0.day >= target }) ?? sections.last else { return }
                    scroll(proxy, to: Self.headerID(section.day))
                }
                // Debounced (matches YearView's own 150ms debounce for its density recompute):
                // `.task(id:)` cancels the previous wait whenever the displayed rows change
                // again before it fires, so a fast scroll reports only where it settles.
                .task(id: displayedRowIDs) {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    guard Date() >= scrollSuppressUntil else { return }
                    guard let top = AgendaScrollTracking.topRowID(displayed: displayedRowIDs,
                                                                  orderedRowIDs: rows.map(\.id)),
                          let day = rowDayLookup[top] else { return }
                    onDayInView(day)
                }
            }
        }
    }

    // MARK: Rows

    /// The minimum height every row had while List's own default minimum row height applied
    /// (measured on iOS 26). The list now sets that minimum to 0 so bare empty-day headers can
    /// be compact, so every other row states the old minimum explicitly to keep its layout.
    private static let rowMinHeight: CGFloat = 52

    private func headerRow(day: Date, todayStart: Date, compact: Bool) -> some View {
        let isToday = day == todayStart
        let tomorrow = Self.calendar.date(byAdding: .day, value: 1, to: todayStart)
        let word: String
        if isToday {
            word = "TODAY"
        } else if day == tomorrow {
            word = "TOMORROW"
        } else {
            word = AgendaFormat.weekdayName(day).uppercased()
        }
        return (Text(word).fontWeight(.bold) + Text("  \(AgendaFormat.shortDate(day))"))
            .font(Fonts.mono(11))
            .tracking(2)
            .foregroundStyle(isToday ? Colors.accent : Colors.textSecondary)
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: compact ? nil : Self.rowMinHeight)
        .listRowSeparator(.hidden)
        .listRowBackground(Colors.background)
        .listRowInsets(EdgeInsets())
    }

    /// One agenda item: the row's visuals with its tap targets laid over them.
    private func itemRow(_ item: AgendaItem, endsSection: Bool, divider: Bool) -> some View {
        let isPending = pending.isPending(item.id)
        let rowView = AgendaRowView(item: item, isPending: isPending)
        let isReminder: Bool = {
            if case .reminder = item.kind { return true }
            return false
        }()
        // The visuals, exactly as before (not tappable, hidden from VoiceOver)...
        return rowView
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
            .modifier(SectionEnd(endsSection: endsSection, divider: divider))
            .frame(minHeight: Self.rowMinHeight)
            // ...with the taps laid over the finished row rectangle, so they cover all of it
            // (padding, section gap and min height included). The checkbox and the "open
            // details" area are non-overlapping sibling `.plain` buttons; see `AgendaRowTargets`
            // for why that keeps the two taps from ever fighting.
            .overlay {
                AgendaRowTargets(
                    looksDone: item.isCompleted || isPending,
                    summary: rowView.accessibilitySummary,
                    onSelect: { onSelect(item) },
                    onToggleComplete: isReminder ? { toggleComplete(item) } : nil
                )
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Colors.background)
            .listRowInsets(EdgeInsets())
    }

    /// The checkbox was tapped. A completed reminder reopens immediately (no grace window); an
    /// incomplete one starts a pending completion, or cancels it if one is already pending.
    /// `item.id` (reminder id + occurrence) is the stable pending key, never a list position.
    private func toggleComplete(_ item: AgendaItem) {
        guard case .reminder(let reminder) = item.kind else { return }
        if reminder.isCompleted {
            store.uncompleteReminder(id: reminder.id)
        } else {
            pending.toggle(key: item.id, reminderID: reminder.id, occurrence: item.occurrence)
        }
    }

    // MARK: Data

    private func makeSections(now: Date) -> [AgendaDay] {
        let range = AgendaWindow.range(around: anchor)
        let items = buildAgendaItems(
            events: store.events,
            reminders: store.reminders,
            in: range,
            // The real today, not the anchor: overdue logic must not move with the window.
            today: now
        )
        return groupAgendaByDay(items, in: range, calendar: Self.calendar)
    }

    private func makeRows(_ sections: [AgendaDay], todayStart: Date) -> [ListRow] {
        var rows: [ListRow] = []
        for (index, section) in sections.enumerated() {
            // A 1pt rule closes every non-empty section but the last, like Fantastical's day
            // dividers. It closes (rather than opens) each section so today's header, where the
            // list rests, sits directly under the grid's own rule instead of doubling it.
            let divider = index < sections.count - 1
            let isBareDay = section.items.isEmpty && section.day != todayStart
            rows.append(.header(day: section.day, compact: isBareDay))
            if section.items.isEmpty {
                // Only today keeps a "No events" row; other empty days are just their header,
                // with no rule, so a run of empty days stays compact.
                if !isBareDay {
                    rows.append(.empty(day: section.day, divider: divider))
                }
            } else {
                for (itemIndex, item) in section.items.enumerated() {
                    let isLast = itemIndex == section.items.count - 1
                    rows.append(.item(item, endsSection: isLast, divider: isLast && divider))
                }
            }
        }
        rows.append(.tail)
        return rows
    }

    /// Maps every row id `makeRows` can produce back to the day it belongs to, so
    /// `AgendaScrollTracking.topRowID`'s top-of-viewport id can be resolved to a day. Mirrors
    /// `makeRows`'s exact branching so it never invents an id that isn't actually a row:
    /// an `.empty` row only exists for today when it has no items — every other empty day
    /// is just its header.
    private func makeRowDayLookup(_ sections: [AgendaDay], todayStart: Date) -> [String: Date] {
        var lookup: [String: Date] = [:]
        for section in sections {
            lookup[Self.headerID(section.day)] = section.day
            if section.items.isEmpty {
                if section.day == todayStart {
                    lookup["empty-\(Int(section.day.timeIntervalSince1970))"] = section.day
                }
            } else {
                for item in section.items {
                    lookup[item.id] = section.day
                }
            }
        }
        return lookup
    }

    // MARK: Scrolling

    private static func headerID(_ day: Date) -> String {
        "day-\(Int(day.timeIntervalSince1970))"
    }

    private func scrollToToday(_ proxy: ScrollViewProxy, todayStart: Date) {
        scroll(proxy, to: Self.headerID(todayStart))
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: String) {
        // Deferred one runloop turn so the rows exist by the time the scroll is applied.
        DispatchQueue.main.async {
            // Re-armed here too (not just in the scrollRequest onChange): this covers the
            // scroll→settle gap in addition to the request→scroll gap, since the debounced
            // scroll-tracking report can otherwise land inside a still-unsuppressed window on a
            // slow settle (e.g. after selectDate re-centers agendaAnchor and buildAgendaItems
            // reruns over the whole display range before this deferred scroll even happens).
            scrollSuppressUntil = Date().addingTimeInterval(0.3)
            proxy.scrollTo(id, anchor: .top)
        }
    }
}

/// Closes a day section: extra breathing room below the last row and, except after the final
/// section, a full-width 1pt separator.
private struct SectionEnd: ViewModifier {
    let endsSection: Bool
    let divider: Bool

    func body(content: Content) -> some View {
        content
            .padding(.bottom, endsSection ? Spacing.sm : 0)
            .overlay(alignment: .bottom) {
                if divider {
                    Rectangle().fill(Colors.separator).frame(height: 1)
                }
            }
    }
}

private extension View {
    func sectionEnd(divider: Bool) -> some View {
        modifier(SectionEnd(endsSection: true, divider: divider))
    }
}
