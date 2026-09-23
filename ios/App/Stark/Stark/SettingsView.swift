// ios/App/Stark/Stark/SettingsView.swift
import SwiftUI

/// A Keyboard toggle (iPhone only) plus About. Storage is just the local Documents directory;
/// there is no iCloud toggle or file picker, unlike the deprecated Expo app's Settings screen.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showFAQ = false
    @AppStorage(SigilKeyboardSetting.key) private var sigilKeyboardBar = SigilKeyboardSetting.defaultValue

    // Read from the bundle, not hardcoded, so these can never drift from the actual build
    // (mirrors the Expo app's About section, which read from `Constants.expoConfig` for the
    // same reason).
    private static let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Stark"
    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    private static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"

    private static let websiteURL = URL(string: "https://stark.caritos.com")!
    private static let developerURL = URL(string: "http://caritos.com")!
    private static let privacyURL = URL(string: "https://stark.caritos.com/privacy")!
    private static let termsURL = URL(string: "https://stark.caritos.com/terms")!

    var body: some View {
        NavigationStack {
            List {
                // No on-screen keyboard on Mac Catalyst, so there is nothing to toggle there.
                #if !targetEnvironment(macCatalyst)
                Section {
                    Toggle("Tag buttons above keyboard", isOn: $sigilKeyboardBar)
                        .foregroundStyle(Colors.text)
                } header: {
                    Text("Keyboard")
                } footer: {
                    Text("Shows + @ % ~ buttons above the keyboard when you type a title, notes, location or search.")
                        .font(.footnote)
                        .foregroundStyle(Colors.textSecondary)
                }
                .listRowBackground(Colors.background)
                #endif

                Section {
                    Button {
                        openURL(Self.websiteURL)
                    } label: {
                        HStack {
                            Text("App Name").foregroundStyle(Colors.text)
                            Spacer()
                            Text(Self.appName).foregroundStyle(Colors.accent)
                        }
                    }
                    LabeledContent("Version") {
                        Text("\(Self.version) (\(Self.build))")
                    }
                    Button {
                        openURL(Self.developerURL)
                    } label: {
                        HStack {
                            Text("Developer").foregroundStyle(Colors.text)
                            Spacer()
                            Text("Eladio Caritos").foregroundStyle(Colors.accent)
                        }
                    }
                    Button("Privacy Policy") { openURL(Self.privacyURL) }
                        .foregroundStyle(Colors.accent)
                    Button("Terms of Service") { openURL(Self.termsURL) }
                        .foregroundStyle(Colors.accent)
                    // In-app, not a link to the website's /support page -- available offline,
                    // like the rest of the app.
                    Button("FAQ") { showFAQ = true }
                        .foregroundStyle(Colors.accent)
                } header: {
                    Text("About")
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
            .sheet(isPresented: $showFAQ) { FAQView() }
        }
        .tint(Colors.accent)
        .preferredColorScheme(.dark)
    }
}
