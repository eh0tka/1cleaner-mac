import AppKit
import SwiftUI

@main
struct OneCleanerMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("1Cleaner", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
                .preferredColorScheme(.light)
                .task {
                    appDelegate.model = model
                    DebugLaunch.apply(to: model)
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    model.navigate(to: .about)
                    model.checkForUpdates()
                }
                Button("Support the Developer…") { model.support = .manual }
            }
            CommandMenu("Scan") {
                Button("Scan") { model.startScan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isBusyScanning || model.cleanup != nil || model.move != nil)
                Button("Stop Scan") { model.stopScan() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.isBusyScanning)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(.light)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor weak var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quit while a cleanup or a move changes files asks first; the window itself can't close
    /// then, since their sheets are open.
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Installing an update swaps the app in a moment and then starts the new copy itself.
        if model?.isInstallingUpdate == true { return .terminateCancel }
        guard let model, model.isChangingFiles else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit while 1Cleaner is working?",
                                   comment: "Alert title when the person quits during a cleanup or a move to another disk")
        alert.informativeText = String(localized: "1Cleaner stops after the current item and removes an unfinished copy, then quits.",
                                       comment: "Alert text when quitting during a cleanup or a move to another disk")
        alert.addButton(withTitle: String(localized: "Keep Working", comment: "Button: don't quit, let the cleanup go on"))
        alert.addButton(withTitle: String(localized: "Stop and Quit", comment: "Button: stop the cleanup or move, then quit"))
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        model.stopForQuit { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

/// DEBUG launch arguments for headless QA: `-autoScan YES` starts a scan on launch, `-openCategory projects`
/// selects a category, `-rescanCategory docker` rescans one category, `-snapshotDir /path` (with `-autoScan YES`) writes PNGs of Overview and every category
/// after the scan, plus `summary.txt`, then quits. Scanning only reads; nothing here removes anything.
enum DebugLaunch {
    @MainActor
    static func apply(to model: AppModel) {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "openCategory"), let category = CategoryID(rawValue: raw) {
            model.destination = .category(category)
        }
        if defaults.bool(forKey: "autoScan") { model.startScan() }
        if defaults.bool(forKey: "analyzeStorage") { model.analyzeStorage() }
        // `-openSupport YES`: opens the Support sheet, to check it in a real window.
        if defaults.bool(forKey: "openSupport") { model.support = .manual }
        if let raw = defaults.string(forKey: "rescanCategory"), let category = CategoryID(rawValue: raw) {
            model.rescan(category)
        }
        // `-debugMoveSource <path> -debugMoveTo <folder> -snapshotDir <dir>`: runs Move to Another Disk on one
        // folder, writes the outcome to move.txt and quits.
        if let source = defaults.string(forKey: "debugMoveSource"), let folder = defaults.string(forKey: "debugMoveTo"),
           let directory = defaults.string(forKey: "snapshotDir"), let target = FileTarget(path: source) {
            let item = CleanupItem(id: source, category: .largeFiles, title: (source as NSString).lastPathComponent,
                                   detail: "", size: 0, removal: .trash([target]))
            Task {
                let outcome = await Mover.move(item, to: folder) { _, _ in }
                try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try? String(describing: outcome).write(toFile: directory + "/move.txt", atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
            return
        }
        // `-installUpdate YES -snapshotDir <dir>` (with `-updateFeed file:///…/version.json`): checks, installs the
        // update and relaunches; a failure is written to install.txt.
        if defaults.bool(forKey: "installUpdate"), let directory = defaults.string(forKey: "snapshotDir") {
            Task {
                try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                model.checkForUpdates()
                while model.isCheckingForUpdates { try? await Task.sleep(for: .milliseconds(200)) }
                guard case .available(let release) = model.updateResult else {
                    try? "no update: \(String(describing: model.updateResult))".write(toFile: directory + "/install.txt", atomically: true, encoding: .utf8)
                    NSApp.terminate(nil)
                    return
                }
                model.installUpdate(release)
                while model.isInstallingUpdate { try? await Task.sleep(for: .milliseconds(200)) }
                try? (model.updateInstallError ?? "relaunching").write(toFile: directory + "/install.txt", atomically: true, encoding: .utf8)
                if model.updateInstallError != nil { NSApp.terminate(nil) }
            }
            return
        }
        // `-checkForUpdates YES -snapshotDir <dir>`: runs Check for Updates against the live site, writes the About
        // screen to update.png and quits.
        if defaults.bool(forKey: "checkForUpdates"), let directory = defaults.string(forKey: "snapshotDir") {
            Task {
                try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                NSApp.activate(ignoringOtherApps: true)
                model.destination = .about
                try? await Task.sleep(for: .seconds(1))
                model.checkForUpdates()
                while model.isCheckingForUpdates { try? await Task.sleep(for: .milliseconds(200)) }
                // Again: the window may have restored its last screen meanwhile.
                model.destination = .about
                try? await Task.sleep(for: .milliseconds(600))
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                    writeWindowImage(window, to: directory + "/update.png")
                }
                NSApp.terminate(nil)
            }
            return
        }
        if let directory = defaults.string(forKey: "snapshotDir") {
            Task { await snapshots(model, directory: directory) }
        }
        #endif
    }

    #if DEBUG
    /// The whole window as the screen shows it (title bar, toolbar, the sidebar's material), which `cacheDisplay`
    /// can't draw; falls back to `cacheDisplay` of the content.
    /// True when a sample of pixels across the image is one color.
    private static func isBlank(_ image: CGImage) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        let first = rep.colorAt(x: image.width / 2, y: image.height / 2)
        for i in 1..<20 {
            let color = rep.colorAt(x: image.width * i / 20, y: image.height * (20 - i) / 21)
            if color != first { return false }
        }
        return true
    }

    @MainActor
    private static func writeWindowImage(_ window: NSWindow, to path: String) {
        let url = URL(fileURLWithPath: path)
        // A locked or sleeping screen gives a blank image; then the frame view is drawn instead.
        if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                               [.boundsIgnoreFraming, .bestResolution]),
           image.width > 1, !isBlank(image) {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            return
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    @MainActor
    private static func snapshots(_ model: AppModel, directory: String) async {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        // Frontmost and key, so the window is drawn active (not dimmed) in the pictures.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
        let started = Date()
        // Without -autoScan the snapshots show the app as it opens (the dashboard from saved stats).
        try? await Task.sleep(for: .seconds(1))
        while (UserDefaults.standard.bool(forKey: "autoScan") && !model.hasScanned) || model.isBusyScanning
                || model.isAnalyzingStorage,
              Date().timeIntervalSince(started) < 900 {
            try? await Task.sleep(for: .seconds(1))
        }
        var summary = "Scan took \(Int(Date().timeIntervalSince(started))) s\n"
        // `-summaryOnly YES`: only summary.txt, no pictures (a locked screen can stall window captures).
        let pictures = !UserDefaults.standard.bool(forKey: "summaryOnly")
        let destinations: [(String, SidebarDestination)] = !pictures ? [] : [("overview", .overview), ("storage", .storage)]
            + CategoryID.allCases.map { ($0.rawValue, .category($0)) } + [("safelist", .safeList), ("about", .about)]
        for (name, destination) in destinations {
            model.destination = destination
            try? await Task.sleep(for: .milliseconds(300))
            // The sidebar echoes the switch back through `navigate(to:)`, which asks about checked items.
            model.pendingDestination = nil
            try? await Task.sleep(for: .milliseconds(900))
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                writeWindowImage(window, to: "\(directory)/\(name).png")
            }
        }
        // The confirmation sheet only; it is closed again without starting the cleanup.
        if pictures {
        model.destination = .overview
        model.prepareCleanup()
        try? await Task.sleep(for: .milliseconds(1200))
        if let sheet = NSApp.windows.compactMap(\.attachedSheet).first, let view = sheet.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(directory)/confirm.png"))
        }
        model.closeCleanup()
        // The Support sheet as it opens after a cleanup.
        model.support = .afterCleanup(freed: 12_400_000_000)
        try? await Task.sleep(for: .milliseconds(1200))
        if let sheet = NSApp.windows.compactMap(\.attachedSheet).first, let view = sheet.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(directory)/support.png"))
        }
        model.support = nil
        }

        for category in CategoryID.allCases {
            let result = model.result(category)
            let selected = model.selectedSize(in: [category])
            summary += "\(category.rawValue): \(result.items.count) items, \(result.totalSize.formattedBytes), "
                + "selected \(selected.formattedBytes)\n"
            for note in result.notes { summary += "  note: \(note)\n" }
            // `-openCategory <id>` lists that category in full.
            let full = UserDefaults.standard.string(forKey: "openCategory") == category.rawValue
            for item in result.items.prefix(full ? 1000 : 8) {
                summary += "  - [\(item.safety.title)] \(item.title) \(item.size.formattedBytes)"
                    + "\(model.isSelected(item) ? " ✓" : "")\(item.lockedReason.map { " 🔒 \($0)" } ?? "") · \(item.detail)\n"
            }
        }
        if let report = model.storage {
            summary += "storage: used \(report.diskUsed.formattedBytes), measured \(report.measured.formattedBytes), "
                + "not measured \(report.notMeasured.formattedBytes)\n"
            for entry in report.sortedBuckets {
                summary += "  \(entry.bucket.rawValue): \(entry.bytes.formattedBytes)\n"
                for folder in (report.folders[entry.bucket] ?? []).prefix(3) {
                    summary += "    - \(PathDisplay.abbreviated(folder.path)) \(folder.bytes.formattedBytes), "
                        + "\(folder.files.count) files listed\n"
                    // Subfolders as the Storage drill-down shows them, two levels.
                    for child in folder.children(of: folder.path).prefix(4) {
                        let target = folder.collapsed(child.path)
                        summary += "        \(PathDisplay.abbreviated(target)) \(child.usage.bytes.formattedBytes), "
                            + "\(child.usage.fileCount) files\n"
                        for grandchild in folder.children(of: target).prefix(3) {
                            summary += "          \(PathDisplay.abbreviated(folder.collapsed(grandchild.path))) "
                                + "\(grandchild.usage.bytes.formattedBytes), \(grandchild.usage.fileCount) files\n"
                        }
                    }
                }
            }
        }
        // The Copy for AI text of the opened category's first item.
        if let raw = UserDefaults.standard.string(forKey: "openCategory"), let category = CategoryID(rawValue: raw),
           let first = model.result(category).items.first {
            let prompt = await AIPrompt.make(for: first)
            try? prompt.write(toFile: "\(directory)/prompt.txt", atomically: true, encoding: .utf8)
        }
        try? summary.write(toFile: "\(directory)/summary.txt", atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
    #endif
}
