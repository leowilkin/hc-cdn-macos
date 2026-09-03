import AppKit
import SwiftUI

@main
enum HackClubCDNApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

// MARK: - Menu bar drop target

/// Sits on top of the status item button so files can be dropped straight onto the menu bar.
final class StatusDropView: NSView {
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var statusButton: NSStatusBarButton? { superview as? NSStatusBarButton }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        statusButton?.highlight(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        statusButton?.highlight(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        statusButton?.highlight(false)
        guard let urls = sender.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty
        else { return false }
        Task { @MainActor in
            UploadManager.shared.add(urls: urls)
            AppDelegate.shared?.showWindow()
        }
        return true
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onClick?() }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var ticker: Timer?
    private var queuedURLs: [URL] = []
    private var launched = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.servicesProvider = self
        buildMainMenu()
        buildStatusItem()
        launched = true

        if !queuedURLs.isEmpty {
            UploadManager.shared.add(urls: queuedURLs)
            queuedURLs = []
        }
        showWindow()

        ticker = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatusItem() }
        }
    }

    // MARK: Window

    func showWindow() {
        if window == nil {
            let hosting = NSHostingView(rootView: RootView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 460),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Hack Club CDN"
            window.contentView = hosting
            window.center()
            window.setFrameAutosaveName("HackClubCDNMain")
            window.isReleasedWhenClosed = false
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.up.circle", accessibilityDescription: "Hack Club CDN")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Hack Club CDN — drop files here"

        if let button = item.button {
            let drop = StatusDropView(frame: button.bounds)
            drop.autoresizingMask = [.width, .height]
            drop.onClick = { [weak self] in Task { @MainActor in self?.showWindow() } }
            button.addSubview(drop)
        }
        statusItem = item
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        if let progress = UploadManager.shared.activeProgress {
            button.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: nil)
            button.image?.isTemplate = true
            button.title = " \(Int(progress * 100))%"
        } else {
            button.image = NSImage(systemSymbolName: "arrow.up.circle", accessibilityDescription: nil)
            button.image?.isTemplate = true
            button.title = ""
        }
    }

    // MARK: File intake

    func application(_ application: NSApplication, open urls: [URL]) {
        if launched {
            Task { @MainActor in
                UploadManager.shared.add(urls: urls)
                showWindow()
            }
        } else {
            queuedURLs.append(contentsOf: urls)
        }
    }

    /// Finder → right-click → Services → Upload to Hack Club CDN
    @objc func uploadToCDN(_ pasteboard: NSPasteboard, userData: String,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else {
            error.pointee = "No files were passed to Hack Club CDN." as NSString
            return
        }
        Task { @MainActor in
            UploadManager.shared.add(urls: urls)
            showWindow()
        }
    }

    // MARK: Lifecycle

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in showWindow() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard UploadManager.shared.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Uploads are still running."
        alert.informativeText = "Quitting now will cancel them."
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Keep Uploading")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    @objc private func openSettings() {
        showWindow()
        NotificationCenter.default.post(name: .openCDNSettings, object: nil)
    }

    // MARK: Menu

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Hack Club CDN",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(services)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Hack Club CDN",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Hack Club CDN",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let open = NSMenuItem(title: "Upload Files…", action: #selector(pickFiles), keyEquivalent: "o")
        open.target = self
        fileMenu.addItem(open)
        let close = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(close)
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    @objc private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        guard panel.runModal() == .OK else { return }
        Task { @MainActor in
            UploadManager.shared.add(urls: panel.urls)
            showWindow()
        }
    }
}
