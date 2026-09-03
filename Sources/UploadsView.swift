import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @ObservedObject var manager = UploadManager.shared
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if manager.settings.apiKey.isEmpty {
                OnboardingView()
            } else {
                DropZone()
                Divider()
                UploadList()
                Divider()
                Footer(showingSettings: $showingSettings)
            }
        }
        .frame(minWidth: 460, minHeight: 380)
        .overlay(alignment: .bottom) { Toast() }
        .animation(.easeInOut(duration: 0.15), value: manager.toast)
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .onReceive(NotificationCenter.default.publisher(for: .openCDNSettings)) { _ in
            showingSettings = true
        }
        .task { await manager.refreshAccount() }
    }
}

// MARK: - Drop zone

struct DropZone: View {
    @ObservedObject private var manager = UploadManager.shared
    @State private var targeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(targeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
            VStack(spacing: 6) {
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 22, weight: .light))
                Text("Drop files here")
                    .font(.callout)
                Text("or right-click in Finder → Services → Upload to Hack Club CDN")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(targeted ? Color.accentColor : Color.secondary)
        }
        .frame(height: 108)
        .padding(12)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            load(providers)
            return true
        }
    }

    private func load(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in manager.add(urls: [url]) }
            }
        }
    }
}

// MARK: - List

struct UploadList: View {
    @ObservedObject private var manager = UploadManager.shared

    var body: some View {
        if manager.items.isEmpty {
            VStack {
                Spacer()
                Text("Uploads will show up here.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(manager.items.reversed()) { item in
                        UploadRow(item: item)
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
    }
}

struct UploadRow: View {
    @ObservedObject var item: UploadItem
    @ObservedObject private var manager = UploadManager.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                detail
            }

            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hovering ? Color.secondary.opacity(0.08) : Color.clear)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = item.doneURL { manager.copy(url, note: "Link copied") }
        }
        .contextMenu {
            if let url = item.doneURL {
                Button("Copy Link") { manager.copy(url, note: "Link copied") }
                Button("Open in Browser") { NSWorkspace.shared.open(URL(string: url)!) }
            }
            Button("Show Original in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.source])
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch item.state {
        case .waiting:
            Text("Waiting…").font(.caption).foregroundStyle(.secondary)
        case .compressing:
            Text("Compressing folder…").font(.caption).foregroundStyle(.secondary)
        case .uploading(let sent, let total):
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: total > 0 ? Double(sent) / Double(total) : 0)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 260)
                Text(total > 0
                     ? "\(ByteCountFormatter.human.string(fromByteCount: sent)) of \(ByteCountFormatter.human.string(fromByteCount: total))"
                     : "Starting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .finalizing:
            Text("Processing on the server…").font(.caption).foregroundStyle(.secondary)
        case .done(let url):
            Text(url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch item.state {
        case .waiting:
            EmptyView()
        case .compressing, .finalizing:
            ProgressView().controlSize(.small)
        case .uploading(let sent, let total):
            // Determinate bar plus a spinner, so a big upload always looks alive.
            HStack(spacing: 8) {
                Text(total > 0 ? "\(Int(Double(sent) / Double(total) * 100))%" : "")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                ProgressView().controlSize(.small)
            }
        case .done(let url):
            Button {
                manager.copy(url, note: "Link copied")
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
        case .failed:
            Button("Retry") { manager.retry(item) }
                .controlSize(.small)
        }
    }
}

// MARK: - Chrome

struct Footer: View {
    @ObservedObject private var manager = UploadManager.shared
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            if let account = manager.account {
                Text(quotaText(account))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if manager.items.contains(where: { $0.state.isFinished }) {
                Button("Clear") { manager.clearFinished() }
                    .controlSize(.small)
            }
            Button("Copy All Links") { manager.copyAllLinks() }
                .controlSize(.small)
                .disabled(manager.items.allSatisfy { $0.doneURL == nil })
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func quotaText(_ account: CDNUser) -> String {
        let used = ByteCountFormatter.human.string(fromByteCount: Int64(account.storage_used))
        guard let limit = account.storage_limit, limit > 0 else { return "\(account.name) · \(used) used" }
        return "\(account.name) · \(used) of \(ByteCountFormatter.human.string(fromByteCount: Int64(limit)))"
    }
}

struct Toast: View {
    @ObservedObject private var manager = UploadManager.shared

    var body: some View {
        if let toast = manager.toast {
            Text(toast)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thickMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.2)))
                .shadow(radius: 8, y: 2)
                .padding(.bottom, 52)
                .transition(.opacity)
        }
    }
}

extension Notification.Name {
    static let openCDNSettings = Notification.Name("openCDNSettings")
}
