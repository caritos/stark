//
//  WatchAddView.swift
//  StarkWatch
//
//  Thin views over `WatchAddModel`: send at once; a clean save closes by itself. The list's + button
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
                case .saved(_, nil):  // a clean save needs no answer: closes by itself
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle).foregroundStyle(.green)
                        .accessibilityLabel("Added")
                        .task {
                            WKInterfaceDevice.current().play(.success)
                            // Long enough to be seen, and for the sheet to finish presenting.
                            try? await Task.sleep(for: .seconds(1))
                            dismiss()
                        }
                case .saved(let notice, let warning?):  // e.g. a calendar that does not sync
                    VStack(spacing: 8) {
                        Text(notice ?? "Added").font(.headline)
                        Text(warning).font(.caption2).foregroundStyle(.orange)
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
