// ios/App/Stark/Stark/AgendaView.swift
import SwiftUI
import StarkKit

/// A request to scroll the agenda to a date. A fresh `token` per request makes tapping the
/// same date twice a *different* value, so `onChange` fires (and scrolls) again.
struct ScrollRequest: Equatable {
    let date: Date
    let token = UUID()
}

/// Day-grouped agenda. Items come from `buildAgendaItems` and are grouped by the start of
/// their `displayDate`'s day (so overdue-pinned reminders sit under today). Today always has a
/// section, even when empty.
struct AgendaView: View {
    @EnvironmentObject private var store: PlannerStore
    let scrollRequest: ScrollRequest?
    let onSelect: (AgendaItem) -> Void

    /// False until the list has been scrolled to today once real data has arrived — the
    /// display window includes the previous 14 days, and the store loads asynchronously after
    /// the first render, so the initial scroll has to be repeated when the days first change.
    @State private var hasSettled = false

    private static let calendar = Calendar(identifier: .gregorian)

    private struct DaySection {
        let day: Date
        let items: [AgendaItem]
    }

    private enum ListRow: Identifiable {
        case header(day: Date)
        case empty(day: Date, divider: Bool)
        case item(AgendaItem, endsSection: Bool, divider: Bool)

        var id: String {
            switch self {
            case .header(let day): return AgendaView.headerID(day)
            case .empty(let day, _): return "empty-\(Int(day.timeIntervalSince1970))"
            case .item(let item, _, _): return item.id
            }
        }
    }

    var body: some View {
        let now = Date()
        let todayStart = Self.calendar.startOfDay(for: now)
        let sections = makeSections(now: now, todayStart: todayStart)
        let rows = makeRows(sections)
        let days = sections.map(\.day)

        ScrollViewReader { proxy in
            List {
                ForEach(rows) { row in
                    switch row {
                    case .header(let day):
                        headerRow(day: day, todayStart: todayStart)
                    case .empty(_, let divider):
                        Text("No events")
                            .font(.subheadline)
                            .foregroundStyle(Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xs)
                            .sectionEnd(divider: divider)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Colors.background)
                            .listRowInsets(EdgeInsets())
                    case .item(let item, let endsSection, let divider):
                        Button {
                            onSelect(item)
                        } label: {
                            AgendaRowView(item: item)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.xs + 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .modifier(SectionEnd(endsSection: endsSection, divider: divider))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Colors.background)
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Colors.separator)
            .scrollContentBackground(.hidden)
            .background(Colors.background)
            .onAppear {
                scrollToToday(proxy, todayStart: todayStart)
            }
            .onChange(of: days) { _, _ in
                guard !hasSettled else { return }
                scrollToToday(proxy, todayStart: todayStart)
                // A list with only today's (empty) section has nothing more to wait for
                // yet; keep re-anchoring until the first real days arrive.
                hasSettled = days.count > 1
            }
            .onChange(of: scrollRequest) { _, request in
                guard let request else { return }
                hasSettled = true
                let target = Self.calendar.startOfDay(for: request.date)
                // First section on/after the requested day, else the last section.
                guard let section = sections.first(where: { $0.day >= target }) ?? sections.last else { return }
                scroll(proxy, to: Self.headerID(section.day))
            }
        }
    }

    // MARK: Rows

    private func headerRow(day: Date, todayStart: Date) -> some View {
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
        .listRowSeparator(.hidden)
        .listRowBackground(Colors.background)
        .listRowInsets(EdgeInsets())
    }

    // MARK: Data

    private func makeSections(now: Date, todayStart: Date) -> [DaySection] {
        let items = buildAgendaItems(
            events: store.events,
            reminders: store.reminders,
            in: AgendaWindow.range(around: now),
            today: now
        )
        // `items` is already sorted (day, then overdue / normal / completed), so appending
        // preserves the within-day order.
        var grouped: [Date: [AgendaItem]] = [:]
        for item in items {
            grouped[Self.calendar.startOfDay(for: item.displayDate), default: []].append(item)
        }
        if grouped[todayStart] == nil { grouped[todayStart] = [] }
        return grouped.keys.sorted().map { DaySection(day: $0, items: grouped[$0] ?? []) }
    }

    private func makeRows(_ sections: [DaySection]) -> [ListRow] {
        var rows: [ListRow] = []
        for (index, section) in sections.enumerated() {
            // A 1pt rule closes every section but the last, like Fantastical's day dividers.
            // It closes (rather than opens) each section so today's header, where the list
            // rests, sits directly under the grid's own rule instead of doubling it.
            let divider = index < sections.count - 1
            rows.append(.header(day: section.day))
            if section.items.isEmpty {
                rows.append(.empty(day: section.day, divider: divider))
            } else {
                for (itemIndex, item) in section.items.enumerated() {
                    let isLast = itemIndex == section.items.count - 1
                    rows.append(.item(item, endsSection: isLast, divider: isLast && divider))
                }
            }
        }
        return rows
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
