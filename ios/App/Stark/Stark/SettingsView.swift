// ios/App/Stark/Stark/SettingsView.swift
import SwiftUI

/// About-only for now — the app has nothing configurable yet (storage is just the local
/// Documents directory; no iCloud toggle, no file picker, unlike the deprecated Expo app's
/// Settings screen). A real settings screen once there's something to configure.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // Read from the bundle, not hardcoded, so these can never drift from the actual build
    // (mirrors the Expo app's About section, which read from `Constants.expoConfig` for the
    // same reason).
    private static let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Stark"
    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    private static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"

    private static let developerURL = URL(string: "http://caritos.com")!
    private static let privacyURL = URL(string: "https://stark.caritos.com/privacy")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Version") {
                        Text("\(Self.version) (\(Self.build))")
                    }
                    Button("Developer") { openURL(Self.developerURL) }
                        .foregroundStyle(Colors.accent)
                    Button("Privacy Policy") { openURL(Self.privacyURL) }
                        .foregroundStyle(Colors.accent)
                } header: {
                    Text(Self.appName)
                }
                .listRowBackground(Colors.background)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Colors.background)
            .listRowSeparatorTint(Colors.separator)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                FlatToolbarButton(title: "Close", placement: .cancellationAction) { dismiss() }
            }
        }
        .tint(Colors.accent)
        .preferredColorScheme(.dark)
    }
}
