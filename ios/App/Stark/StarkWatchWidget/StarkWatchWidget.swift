//
//  StarkWatchWidget.swift
//  StarkWatchWidget
//
//  The watch complications ("Up Next"). They read the snapshot the iPhone pushed, from the
//  watch-side App Group, and never touch EventKit. All text decisions live in StarkKit's
//  `WatchComplication`; this file only draws them.
//

import StarkKit
import SwiftUI
import WidgetKit

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let content: WatchComplicationContent
}

struct ComplicationProvider: TimelineProvider {
    private let store = UserDefaultsSnapshotStore()

    func placeholder(in context: Context) -> ComplicationEntry {
        let now = Date()
        let line = WidgetLockLine(time: "9:00 AM", title: "Standup")
        return ComplicationEntry(date: now, content: WatchComplicationContent(
            message: nil, lines: [line], inline: line, count: 1))
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        completion(entries().first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let list = entries()
        // The midnight entries lie far ahead, so they do not delay the reload below.
        // Reload within the hour at the latest: a newer snapshot also reloads us when the watch app saves it.
        let reload = WatchComplication.reloadDate(after: Date(), entryDates: list.map(\.date))
        completion(Timeline(entries: list, policy: .after(reload)))
    }

    private func entries() -> [ComplicationEntry] {
        let now = Date()
        let snapshot = store.load()
        let calendar = Calendar.current
        let dates = WatchComplication.entryDates(snapshot: snapshot, now: now, calendar: calendar)
        return WatchDateFace.timelineDates(dates, now: now, calendar: calendar).map {
            ComplicationEntry(date: $0, content: WatchComplication.content(snapshot: snapshot, now: $0,
                                                                           calendar: calendar))
        }
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryCorner: corner
            default: rectangular
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var content: WatchComplicationContent { entry.content }

    @ViewBuilder private var inline: some View {
        if let message = content.message {
            Text(message)
        } else if let line = content.inline {
            Text(line.text).privacySensitive()
        } else {
            Text(WatchComplication.nothingMessage)
        }
    }

    @ViewBuilder private var rectangular: some View {
        if let message = content.message {
            Text(message)
                .font(.caption)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(content.lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 4) {
                        if let time = line.time {
                            Text(time).fontWeight(.semibold).widgetAccentable()
                        }
                        Text(line.title).privacySensitive()
                    }
                    .font(.caption)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // The round and corner styles show today's date, which needs nothing from the iPhone.
    private var face: WatchDateFace { WatchDateFace(date: entry.date) }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Text(face.weekday).font(.caption2.weight(.semibold)).foregroundStyle(.red).widgetAccentable()
                Text(face.day).font(.title2.weight(.semibold))
            }
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(face.accessibilityLabel)
        }
    }

    private var corner: some View {
        Text(face.day)
            .font(.title2.weight(.semibold))
            .widgetLabel { Text(face.weekday).foregroundStyle(.red) }
            .accessibilityLabel(face.accessibilityLabel)
    }
}

struct StarkWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StarkWatchWidget", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("Up Next")
        .description("Your next events and reminders, or today's date.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .accessoryCorner])
    }
}
