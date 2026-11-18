import EventKit
import StarkKit
import SwiftUI
import WidgetKit

/// What one timeline entry shows. The widget never asks for Calendar access: without it the
/// entry says to open Stark.
enum AgendaState {
    case needsAccess
    case items([WidgetItem])
}

struct AgendaEntry: TimelineEntry {
    let date: Date
    let state: AgendaState
}

struct AgendaProvider: TimelineProvider {
    private let provider = EventKitProvider()

    func placeholder(in context: Context) -> AgendaEntry {
        let now = Date()
        let sample = [
            WidgetItem(id: "p1", title: "Team sync", isReminder: false, isAllDay: false, start: now,
                       end: now.addingTimeInterval(3600), colorHex: nil, isOverdue: false),
            WidgetItem(id: "p2", title: "Pay rent", isReminder: true, isAllDay: true, start: now, end: nil,
                       colorHex: nil, isOverdue: false),
            WidgetItem(id: "p3", title: "Lunch", isReminder: false, isAllDay: false,
                       start: now.addingTimeInterval(7200), end: nil, colorHex: nil, isOverdue: false),
        ]
        return AgendaEntry(date: now, state: .items(sample))
    }

    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await entries().first ?? placeholder(in: context)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        Task {
            let list = await entries()
            let end = list.last?.date ?? Date()
            // Reload at the last entry (or in an hour when only one): the fetch window is two days.
            let reload = list.count > 1 ? end : Date().addingTimeInterval(3600)
            completion(Timeline(entries: list, policy: .after(reload)))
        }
    }

    private func entries() async -> [AgendaEntry] {
        let now = Date()
        guard provider.accessState() == .granted else {
            return [AgendaEntry(date: now, state: .needsAccess)]
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 2, to: start) else { return [] }
        let excluded = UserDefaults(suiteName: SelectionMirror.suiteName)
            .map(SelectionMirror.excludedIDs(from:)) ?? []
        let snapshot: AppleSnapshot
        do {
            // Completed reminders are not shown, so the completed window is empty.
            snapshot = try await provider.fetch(events: start...end, reminders: now...now)
        } catch {
            return [AgendaEntry(date: now, state: .items([]))]
        }
        let dates = WidgetAgenda.timelineDates(events: snapshot.events, reminders: snapshot.reminders,
                                               excluded: excluded, now: now, calendar: calendar)
        return dates.map { date in
            AgendaEntry(date: date, state: .items(
                WidgetAgenda.items(events: snapshot.events, reminders: snapshot.reminders, excluded: excluded,
                                   now: date, limit: 5, calendar: calendar)))
        }
    }
}

struct AgendaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AgendaEntry

    var body: some View {
        content
            .containerBackground(.background, for: .widget)
    }

    @ViewBuilder private var content: some View {
        switch entry.state {
        case .needsAccess:
            Text("Open Stark to allow Calendar access")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .items(let items):
            if family == .systemMedium {
                MediumView(date: entry.date, items: Array(items.prefix(5)))
            } else {
                SmallView(items: Array(items.prefix(3)))
            }
        }
    }
}

private struct EmptyStateView: View {
    var body: some View {
        Text("Nothing coming up")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SmallView: View {
    let items: [WidgetItem]
    var body: some View {
        if items.isEmpty {
            EmptyStateView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { RowView(item: $0, stacked: true) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MediumView: View {
    let date: Date
    let items: [WidgetItem]
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 34, weight: .light))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(width: 48, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            if items.isEmpty {
                EmptyStateView()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { RowView(item: $0, stacked: false) }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// One row: calendar-colour dot (filled for an event, a hollow circle for a reminder), the title
/// and the time. `stacked` puts the time under the title (Small); otherwise it sits before it.
private struct RowView: View {
    let item: WidgetItem
    let stacked: Bool

    private var tint: Color {
        if item.isOverdue { return .red }
        return item.colorRGB.map { Color(hex: $0) } ?? .accentColor
    }

    private var time: String? { WidgetRowText.time(item) }

    var body: some View {
        HStack(alignment: stacked ? .top : .center, spacing: 6) {
            marker.padding(.top, stacked ? 3 : 0)
            if stacked {
                VStack(alignment: .leading, spacing: 0) {
                    title
                    if let time { timeText(time) }
                }
            } else {
                // The column is always reserved so titles line up when a row has no time.
                Group { if let time { timeText(time) } else { Color.clear } }
                    .frame(width: 52, alignment: .leading)
                title
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetRowText.accessibilityLabel(item))
    }

    @ViewBuilder private var marker: some View {
        if item.isReminder {
            Circle().strokeBorder(tint, lineWidth: 1.5).frame(width: 9, height: 9)
        } else {
            Circle().fill(tint).frame(width: 9, height: 9)
        }
    }

    private var title: some View {
        Text(item.title.isEmpty ? "Untitled" : item.title)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(item.isOverdue ? Color.red : Color.primary)
    }

    private func timeText(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
    }
}

extension Color {
    /// `0xRRGGBB`: an Apple calendar's own colour (data, not styling).
    fileprivate init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

struct StarkAgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StarkAgendaWidget", provider: AgendaProvider()) { entry in
            AgendaWidgetView(entry: entry)
        }
        .configurationDisplayName("Up Next")
        .description("Your next events and reminders.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
