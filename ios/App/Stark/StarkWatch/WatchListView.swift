//
//  WatchListView.swift
//  StarkWatch
//
//  Thin views over `WatchAgendaModel`: a message per state, rows for items, an "Updated" footer.
//

import StarkKit
import SwiftUI
import WatchKit

struct WatchListView: View {
    let model: WatchAgendaModel
    let addModel: WatchAddModel
    @State private var adding = false

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
                    if model.waitingRows.isEmpty { Message("Nothing coming up") }
                case .failed(let text):
                    Message(text)
                case .items(let rows):
                    // A repeating event's today and tomorrow rows share one id, so key on position too.
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in WatchRowView(row: row, model: model) }
                }
                ForEach(Array(model.waitingRows.enumerated()), id: \.offset) { _, row in
                    WatchRowView(row: row, model: model)
                }
                if let error = model.lastError {
                    Text(error).font(.caption2).foregroundStyle(.red)
                }
                FooterView(model: model)
            }
            .navigationTitle("Up Next")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add")
                }
            }
            .sheet(isPresented: $adding) { WatchAddView(model: addModel) }
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
    let model: WatchAgendaModel

    var body: some View {
        let item = row.item
        let waiting = model.waiting(row)
        HStack(spacing: 8) {
            if item.isReminder {
                Button {
                    Task {
                        // Failure shows the row again with the message; success is a click.
                        switch await model.complete(row) {
                        case .sent, .queued: WKInterfaceDevice.current().play(.success)
                        case .failed: WKInterfaceDevice.current().play(.failure)
                        case .ignored: break
                        }
                    }
                } label: {
                    Image(systemName: waiting ? "clock" : "circle")
                        .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                .disabled(waiting)
                .accessibilityLabel("Complete \(item.title)")
            } else {
                Circle().fill(dotColor).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(2)
                if let time = WidgetRowText.time(item) {
                    Text(time).font(.caption2)
                        .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
                }
                if waiting {
                    Text("Waiting for iPhone").font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .modifier(CombineIfEvent(isEvent: !item.isReminder))
    }

    private var dotColor: Color {
        guard let rgb = row.item.colorRGB else { return .blue }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }
}

private struct CombineIfEvent: ViewModifier {
    let isEvent: Bool
    func body(content: Content) -> some View {
        if isEvent { content.accessibilityElement(children: .combine) } else { content }
    }
}

private struct FooterView: View {
    let model: WatchAgendaModel

    var body: some View {
        if let updated = model.updatedAt {
            // Re-checks staleness every minute even when nothing else changes.
            TimelineView(.periodic(from: .now, by: 60)) { _ in
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
}
