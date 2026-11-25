//
//  WatchListView.swift
//  StarkWatch
//
//  Thin views over `WatchAgendaModel`: a message per state, rows for items, an "Updated" footer.
//

import StarkKit
import SwiftUI

struct WatchListView: View {
    let model: WatchAgendaModel

    var body: some View {
        NavigationStack {
            List {
                switch model.state {
                case .waitingForPhone:
                    Message("Open Stark on your iPhone")
                case .accessNeeded(let text):
                    Message(text)
                case .noSources:
                    Message("Nothing is syncing yet")
                case .empty:
                    Message("Nothing coming up")
                case .failed(let text):
                    Message(text)
                case .items(let rows):
                    ForEach(rows, id: \.item.id) { WatchRowView(row: $0) }
                }
                FooterView(model: model)
            }
            .navigationTitle("Up Next")
        }
    }
}

private struct Message: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
    }
}

struct WatchRowView: View {
    let row: WatchSnapshotRow

    var body: some View {
        let item = row.item
        HStack(spacing: 8) {
            if item.isReminder {
                Image(systemName: "circle")
                    .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
            } else {
                Circle().fill(dotColor).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(2)
                if let time = WidgetRowText.time(item) {
                    Text(time).font(.caption2)
                        .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dotColor: Color {
        guard let rgb = row.item.colorRGB else { return .blue }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }
}

private struct FooterView: View {
    let model: WatchAgendaModel

    var body: some View {
        if let updated = model.updatedAt {
            VStack(alignment: .leading, spacing: 2) {
                if model.stale() {
                    Text("Out of date, open Stark on your iPhone").foregroundStyle(.orange)
                }
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
    }
}
