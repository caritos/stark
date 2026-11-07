// ios/App/Stark/Stark/ClaudeCodeSettingsView.swift
import SwiftUI
import UIKit
import StarkKit

/// Pairs Stark with Claude Code on the Mac: shows the shared secret (hidden until asked),
/// copies it to the pasteboard (local only, expires), and resets it. All logic is in StarkKit
/// (`BridgePairing`, `BridgeAuth`); Keychain errors are shown, never swallowed.
struct ClaudeCodeSettingsView: View {
    let secrets: SecretStore
    @State private var secret: Data?
    @State private var reveal = false
    @State private var errorText: String?
    @State private var confirmReset = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                LabeledContent("Status") {
                    Text(errorText != nil ? "Unavailable" : (secret == nil ? "No secret yet" : "Secret ready"))
                }
                if let secret {
                    Toggle("Show secret", isOn: $reveal)
                        .foregroundStyle(Colors.text)
                    if reveal {
                        Text(BridgeAuth.displayString(for: secret))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Colors.text)
                            .textSelection(.disabled)
                    }
                    Button("Copy secret") { copy(secret) }
                        .foregroundStyle(Colors.accent)
                    Button("Reset pairing") { confirmReset = true }
                        .foregroundStyle(Colors.accent)
                }
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Colors.accent)
                }
            } footer: {
                Text("Lets Claude Code on your Mac add tasks to Stark. Stark still makes no network connections.")
                    .font(.footnote)
                    .foregroundStyle(Colors.textSecondary)
            }
            .listRowBackground(Colors.background)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Colors.background)
        .listRowSeparatorTint(Colors.separator)
        .navigationTitle("Claude Code")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset pairing?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset pairing") { resetPairing() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Claude Code on your Mac must be paired again with the new secret.")
        }
        .onAppear(perform: ensurePaired)
        .onDisappear { reveal = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { reveal = false }
        }
    }

    private func ensurePaired() {
        do {
            secret = try BridgePairing.ensureSecret(in: secrets)
            errorText = nil
        } catch {
            secret = nil
            reveal = false
            errorText = "Couldn't read the pairing secret: \(error)"
        }
    }

    private func resetPairing() {
        do {
            secret = try BridgePairing.reset(in: secrets)
            reveal = false
            errorText = nil
        } catch {
            secret = nil
            reveal = false
            errorText = "Couldn't reset pairing: \(error)"
        }
    }

    private func copy(_ secret: Data) {
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: BridgeAuth.displayString(for: secret)]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]
        )
    }
}
