//
//  WatchAddView.swift
//  StarkWatch
//
//  Thin views over `WatchAddModel`: send at once, then the result. The list's + button
//  opens the system input itself; the text field here is the fallback.
//  Dictation uses the system's speech recognition (Apple may process it).
//

import StarkKit
import SwiftUI
import WatchKit

struct WatchAddView: View {
    let model: WatchAddModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle:
                    VStack(spacing: 8) {
                        TextField("Say or type", text: $text)
                            .onSubmit { model.add(text); text = "" }
                        Text("Dictation is processed by Apple.").font(.caption2).foregroundStyle(.secondary)
                    }
                case .confirming, .sending:  // .confirming lasts only until the send starts
                    ProgressView("Sending")
                case .waiting:
                    VStack(spacing: 8) {
                        Text("Waiting for iPhone").foregroundStyle(.orange)
                        Text("It will be added when your iPhone answers.").font(.caption2)
                        Button("Done") { model.cancel(); dismiss() }
                    }
                case .saved(let notice, let warning):
                    VStack(spacing: 8) {
                        Text(notice ?? "Added").font(.headline)
                        if let draft = model.draft {  // what was heard, so a mistake is noticed
                            Text(draft.title).lineLimit(3)
                            Text(draft.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        if let warning { Text(warning).font(.caption2).foregroundStyle(.orange) }
                        Button("Done") { model.cancel(); dismiss() }
                    }
                    .onAppear { WKInterfaceDevice.current().play(.success) }
                case .failed(let message):
                    VStack(spacing: 8) {
                        Text(message).font(.caption).foregroundStyle(.red)
                        Button("Retry") { Task { await model.confirm() } }
                        Button("Cancel", role: .cancel) { model.cancel(); dismiss() }
                    }
                }
            }
            .navigationTitle("Add")
            .onDisappear { model.cancel() }
        }
    }
}
