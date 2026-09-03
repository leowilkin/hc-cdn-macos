import AppKit
import Combine
import Foundation

enum UploadState {
    case waiting
    case compressing
    case uploading(sent: Int64, total: Int64)
    case finalizing
    case done(url: String)
    case failed(String)

    var isFinished: Bool {
        if case .done = self { return true }
        if case .failed = self { return true }
        return false
    }
}

final class UploadItem: ObservableObject, Identifiable {
    let id = UUID()
    /// The file the user picked. For a dropped folder this stays the folder, so the row reads sensibly.
    let source: URL
    let displayName: String
    @Published var state: UploadState = .waiting

    init(source: URL) {
        self.source = source
        self.displayName = source.lastPathComponent
    }

    var icon: NSImage { NSWorkspace.shared.icon(forFile: source.path) }

    var doneURL: String? {
        if case .done(let url) = state { return url }
        return nil
    }
}

@MainActor
final class UploadManager: ObservableObject {
    static let shared = UploadManager()

    @Published private(set) var items: [UploadItem] = []
    @Published var settings: Settings = ConfigStore.load()
    @Published var toast: String?
    @Published var account: CDNUser?

    private var pending: [UploadItem] = []
    private var active = 0
    private let maxConcurrent = 3
    private var toastTask: Task<Void, Never>?

    /// Overall progress across everything still in flight, or nil when idle.
    var activeProgress: Double? {
        let live = items.filter { !$0.state.isFinished }
        guard !live.isEmpty else { return nil }
        var sent = 0.0
        for item in live {
            if case .uploading(let s, let t) = item.state, t > 0 { sent += Double(s) / Double(t) }
            if case .finalizing = item.state { sent += 1 }
        }
        return sent / Double(live.count)
    }

    var isBusy: Bool { activeProgress != nil }

    func saveSettings() {
        ConfigStore.save(settings)
        objectWillChange.send()
    }

    // MARK: Queueing

    func add(urls: [URL]) {
        let fresh = urls.map { UploadItem(source: $0) }
        guard !fresh.isEmpty else { return }
        items.append(contentsOf: fresh)
        pending.append(contentsOf: fresh)
        pump()
    }

    func retry(_ item: UploadItem) {
        item.state = .waiting
        pending.append(item)
        pump()
    }

    func clearFinished() {
        items.removeAll { $0.state.isFinished }
    }

    private func pump() {
        while active < maxConcurrent, !pending.isEmpty {
            let item = pending.removeFirst()
            active += 1
            Task { await run(item) }
        }
    }

    private func run(_ item: UploadItem) async {
        defer {
            active -= 1
            pump()
        }

        let key = settings.apiKey
        guard !key.isEmpty else {
            item.state = .failed(CDNError.noAPIKey.localizedDescription)
            return
        }

        var payload = item.source
        var scratch: URL?

        if isDirectory(item.source) {
            guard settings.zipFolders else {
                item.state = .failed("Folders aren't supported. Turn on \"Zip folders\" in Settings.")
                return
            }
            item.state = .compressing
            do {
                let zipped = try await zip(item.source)
                payload = zipped
                scratch = zipped
            } catch {
                item.state = .failed(error.localizedDescription)
                return
            }
        }

        defer { if let scratch { try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent()) } }

        item.state = .uploading(sent: 0, total: 0)
        do {
            let upload = try await CDNClient.shared.upload(fileURL: payload, apiKey: key) { sent, total in
                Task { @MainActor in
                    guard !item.state.isFinished else { return }
                    if total > 0, sent >= total {
                        item.state = .finalizing
                    } else {
                        item.state = .uploading(sent: sent, total: total)
                    }
                }
            }
            item.state = .done(url: upload.url)
            if settings.autoCopy { copy(upload.url, note: "Link copied") }
            if settings.playSound { NSSound(named: "Glass")?.play() }
            Task { await refreshAccount() }
        } catch {
            item.state = .failed(error.localizedDescription)
            if settings.playSound { NSSound(named: "Basso")?.play() }
        }
    }

    // MARK: Helpers

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// Shells out to `ditto` so the archive matches what Finder's "Compress" produces.
    private func zip(_ folder: URL) async throws -> URL {
        let box = FileManager.default.temporaryDirectory
            .appendingPathComponent("hc-cdn-zip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        let out = box.appendingPathComponent(folder.lastPathComponent + ".zip")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, out.path]
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    continuation.resume(throwing: CDNError.badResponse(
                        status: Int(proc.terminationStatus), text: "Could not compress the folder."))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    func copy(_ string: String, note: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        showToast(note)
    }

    func copyAllLinks() {
        let links = items.compactMap(\.doneURL)
        guard !links.isEmpty else { return }
        copy(links.joined(separator: "\n"), note: "\(links.count) link\(links.count == 1 ? "" : "s") copied")
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    func refreshAccount() async {
        guard !settings.apiKey.isEmpty else { account = nil; return }
        account = try? await CDNClient.shared.me(apiKey: settings.apiKey)
    }
}

extension ByteCountFormatter {
    static let human: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
