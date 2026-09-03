import AppKit
import SwiftUI

private let apiKeysURL = URL(string: "https://cdn.hackclub.com/api_keys")!

struct OnboardingView: View {
    @ObservedObject private var manager = UploadManager.shared
    @State private var key = ""
    @State private var checking = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
            Text("Connect your Hack Club CDN account")
                .font(.headline)
            Text("Create an API key, then paste it below. It's stored in your Application Support folder and never leaves this Mac except to cdn.hackclub.com.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            Link("Create an API key ↗", destination: apiKeysURL)
                .font(.callout)

            SecureField("sk_cdn_…", text: $key)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 340)
                .onSubmit(verify)

            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }

            Button(action: verify) {
                if checking { ProgressView().controlSize(.small) } else { Text("Connect") }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(key.isEmpty || checking)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func verify() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !checking else { return }
        checking = true
        problem = nil
        Task {
            do {
                let user = try await CDNClient.shared.me(apiKey: trimmed)
                manager.settings.apiKey = trimmed
                manager.saveSettings()
                manager.account = user
            } catch {
                problem = error.localizedDescription
            }
            checking = false
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var manager = UploadManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var status: String?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("API key").font(.callout.weight(.medium))
                HStack {
                    SecureField("sk_cdn_…", text: $key)
                        .textFieldStyle(.roundedBorder)
                    Button(action: verify) {
                        if checking { ProgressView().controlSize(.small) } else { Text("Verify & Save") }
                    }
                    .disabled(key.isEmpty || checking)
                }
                HStack {
                    Link("Manage keys at cdn.hackclub.com ↗", destination: apiKeysURL).font(.caption)
                    Spacer()
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                }
            }

            Divider()

            Toggle("Copy the link automatically when an upload finishes", isOn: binding(\.autoCopy))
            Toggle("Play a sound on finish", isOn: binding(\.playSound))
            Toggle("Zip folders before uploading", isOn: binding(\.zipFolders))

            Divider()

            Text("Finder integration")
                .font(.callout.weight(.medium))
            Text("Right-click any file → Services → Upload to Hack Club CDN. You can give it a keyboard shortcut in System Settings → Keyboard → Keyboard Shortcuts → Services. Dragging files onto the dock or menu bar icon works too.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { key = manager.settings.apiKey }
    }

    private func binding(_ path: WritableKeyPath<Settings, Bool>) -> Binding<Bool> {
        Binding(
            get: { manager.settings[keyPath: path] },
            set: { manager.settings[keyPath: path] = $0; manager.saveSettings() }
        )
    }

    private func verify() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !checking else { return }
        checking = true
        status = nil
        Task {
            do {
                let user = try await CDNClient.shared.me(apiKey: trimmed)
                manager.settings.apiKey = trimmed
                manager.saveSettings()
                manager.account = user
                status = "Signed in as \(user.name)"
            } catch {
                status = error.localizedDescription
            }
            checking = false
        }
    }
}
