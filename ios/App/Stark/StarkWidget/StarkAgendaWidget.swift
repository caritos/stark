import SwiftUI
import WidgetKit

// Placeholder (plan Task 2): the provider, EventKit fetch and real views come in Task 3.
struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct StarkAgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StarkAgendaWidget", provider: PlaceholderProvider()) { _ in
            Text("Stark")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Up Next")
        .description("Your next events and reminders.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
