import AppKit
import Foundation

/// Every scanner of a full scan. They run in parallel; each fills its categories when it finishes.
enum ScannerCatalog {
    static let all: [any Scanner] = [
        ProjectScanner(),
        XcodeScanner(),
        SimulatorScanner(),
        AndroidScanner(),
        LocationScanner(category: .packageCaches, locations: KnownLocations.packageCaches),
        EditorsScanner(),
        DockerScanner(),
        LocationScanner(category: .aiModels, locations: KnownLocations.aiModels),
        AgentsScanner(),
        AppsScanner(),
        LeftoversScanner(),
        AppCachesScanner(),
        LocationScanner(category: .logs, locations: [
            Location("Library/Logs", naming: .appName, perChild: true),
        ]),
        BrowserCachesScanner(),
        InstallersScanner(),
        OldDownloadsScanner(),
        TemporaryScanner(),
        DevicesScanner(),
        TrashScanner(),
    ]
}

/// `~/Library/Caches` per app, without the caches that other categories show.
struct AppCachesScanner: Scanner {
    var categories: [CategoryID] { [.appCaches] }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        let caches = context.homePath("Library/Caches")
        let ownID = Bundle.main.bundleIdentifier ?? ""
        var candidates = FileInfo.children(caches)
            .filter {
                !$0.hasPrefix(".") && !KnownLocations.claimedCacheFolders.contains($0) && $0 != ownID
                    && !KnownLocations.isSyncServiceData(caches + "/" + $0)
            }
            .map { name in
                LocationScanner.Candidate(
                    paths: [caches + "/" + name],
                    title: AppNames.name(forFolder: name),
                    detail: "~/Library/Caches/" + name
                )
            }
        // Copies Mail saves when you open an attachment; the message keeps the original.
        let mailDownloads = context.homePath("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
        if FileInfo.exists(mailDownloads) {
            candidates.append(LocationScanner.Candidate(
                paths: [mailDownloads],
                title: String(localized: "Mail attachment copies", comment: "App Caches row title"),
                detail: String(localized: "Opened attachments; the messages keep the originals",
                               comment: "Detail of the Mail attachment copies row")
            ))
        }
        // Caches of App Store apps live in their containers; macOS lets 1Cleaner read them only with Full Disk Access.
        if context.fullDiskAccess { candidates += Self.containerCaches(context) }
        var items = await LocationScanner.measure(candidates, category: .appCaches, context: context)
        items += await Self.webCachesInsideAppData(context)
        return [.appCaches: ScanOutput(items: items.sorted { $0.size > $1.size })]
    }

    /// `Containers/<id>/Data/Library/Caches` and `Group Containers/<group>/Library/Caches`.
    static func containerCaches(_ context: ScanContext) -> [LocationScanner.Candidate] {
        let ownID = Bundle.main.bundleIdentifier ?? ""
        var result: [LocationScanner.Candidate] = []
        let containers = context.homePath("Library/Containers")
        for id in FileInfo.children(containers) where !id.hasPrefix(".") && id != ownID {
            let path = containers + "/" + id + "/Data/Library/Caches"
            guard FileInfo.isDirectory(path), !KnownLocations.isSyncServiceData(path) else { continue }
            result.append(LocationScanner.Candidate(paths: [path], title: AppNames.name(forFolder: id),
                                                    detail: PathDisplay.abbreviated(path)))
        }
        let groups = context.homePath("Library/Group Containers")
        for group in FileInfo.children(groups) where !group.hasPrefix(".") {
            let path = groups + "/" + group + "/Library/Caches"
            guard FileInfo.isDirectory(path), !KnownLocations.isSyncServiceData(path) else { continue }
            result.append(LocationScanner.Candidate(paths: [path], title: AppNames.name(forFolder: appID(ofGroup: group)),
                                                    detail: PathDisplay.abbreviated(path)))
        }
        return result
    }

    /// `group.com.tencent.xin` → `com.tencent.xin`; `6N38VWS5BX.ru.keepcoder.Telegram` → `ru.keepcoder.Telegram`.
    static func appID(ofGroup group: String) -> String {
        var id = group
        if id.hasPrefix("group.") { id.removeFirst("group.".count) }
        let parts = id.split(separator: ".", maxSplits: 1)
        if parts.count == 2, parts[0].count == 10, parts[0].allSatisfy({ $0.isUppercase || $0.isNumber }) {
            id = String(parts[1])
        }
        if id.hasPrefix("group.") { id.removeFirst("group.".count) }
        return id
    }

    /// Chromium/Electron cache folders inside an app's own data (Claude, Slack, Discord, ...): the app rebuilds
    /// them. Editors have their own category. Locked while the app runs, since it holds these files open.
    static let webCacheFolders = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "GraphiteDawnCache",
        "ShaderCache", "Service Worker/CacheStorage",
    ]

    static func webCachesInsideAppData(_ context: ScanContext) async -> [CleanupItem] {
        let support = context.homePath("Library/Application Support")
        // Editors have their own category; agents that aren't installed are offered whole in AI Agents.
        let editors: Set<String> = Set(["Code", "Cursor", "Windsurf"])
            .union(AgentsScanner.uninstalledAppSupportFolders(home: context.home))
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName?.lowercased() })
        let apps: [(name: String, paths: [String])] = FileInfo.children(support).compactMap { name in
            guard !name.hasPrefix("."), !editors.contains(name), !name.hasPrefix("com.apple.") else { return nil }
            let paths = webCacheFolders.map { support + "/" + name + "/" + $0 }.filter(FileInfo.isDirectory)
            return paths.isEmpty ? nil : (name, paths)
        }
        let items: [CleanupItem?] = await Concurrency.map(apps.map(\.name)) { name -> CleanupItem? in
            guard let paths = apps.first(where: { $0.name == name })?.paths else { return nil }
            var bytes: Int64 = 0
            for path in paths { bytes += FileSizer.measure(path, progress: context.progress).bytes }
            let title = AppNames.name(forFolder: name)
            let targets = paths.compactMap(FileTarget.init(path:)).map { target in
                var target = target
                target.usedWhileRunning = [title.lowercased(), name.lowercased()]
                return target
            }
            guard bytes >= ScanContext.minimumItemSize, !targets.isEmpty else { return nil }
            return CleanupItem(
                id: support + "/" + name + "#webcache",
                category: .appCaches,
                title: title,
                badge: String(localized: "Inside app data", comment: "Badge of web caches inside an app's own data folder"),
                detail: String(localized: "Web caches in ~/Library/Application Support/\(name)",
                               comment: "App Caches row detail; %@ is an app's folder name"),
                size: bytes,
                removal: .trash(targets),
                lockedReason: running.contains(title.lowercased()) || running.contains(name.lowercased())
                    ? String(localized: "Running. Quit \(title) to clean its caches.",
                             comment: "Why a row can't be selected; %@ is an app name") : nil
            )
        }
        return items.compactMap { $0 }
    }
}

/// Disk images and installer packages in Downloads and Desktop, two folder levels deep.
struct InstallersScanner: Scanner {
    static let extensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]

    var categories: [CategoryID] { [.installers] }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        var paths: [String] = []
        var unreadable = false
        for folder in ["Downloads", "Desktop"] {
            let root = context.homePath(folder)
            guard FileInfo.isDirectory(root) else { continue }
            FileSizer.walk(root) { entry in
                let info = Int32(entry.pointee.fts_info)
                if info == FTS_DNR || info == FTS_ERR {
                    unreadable = true
                    return .continue
                }
                let name = entry.name
                let isInstaller = Self.extensions.contains((name as NSString).pathExtension.lowercased())
                if isInstaller, info == FTS_F || info == FTS_D {
                    paths.append(entry.path)
                    return .skip
                }
                if info == FTS_D, entry.pointee.fts_level >= 2 || name.hasPrefix(".") || name.hasSuffix(".app") {
                    return .skip
                }
                return .continue
            }
        }
        let items: [CleanupItem?] = await Concurrency.map(paths) { path -> CleanupItem? in
            let measurement = FileSizer.measure(path)
            guard let target = FileTarget(watching: path) else { return nil }
            let added = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.addedToDirectoryDateKey]))?
                .addedToDirectoryDate ?? FileInfo.modificationDate(path)
            return CleanupItem(
                id: path,
                category: .installers,
                title: (path as NSString).lastPathComponent,
                detail: PathDisplay.abbreviated((path as NSString).deletingLastPathComponent)
                    + (added.map {
                        " · " + String(localized: "added \($0.relativeDescription)",
                                       comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
                    } ?? ""),
                size: measurement.bytes,
                removal: .trash([target]),
                date: added
            )
        }
        var output = ScanOutput(items: items.compactMap { $0 }.sorted { $0.size > $1.size })
        if unreadable {
            output.notes.append(String(localized: "Some folders couldn't be read. Allow access when macOS asks.",
                                       comment: "Note above a list when macOS denied access to some folders"))
        }
        return [.installers: output]
    }
}

/// The Trash's size. Emptied with its own button through Finder.
struct TrashScanner: Scanner {
    var categories: [CategoryID] { [.trash] }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        let measurement = FileSizer.measure(context.homePath(".Trash"))
        var output = ScanOutput()
        output.items = [CleanupItem(
            id: "trash",
            category: .trash,
            title: String(localized: "Trash", comment: "Category: the macOS Trash"),
            detail: measurement.rootReadable
                ? String(localized: "\(measurement.files) files", comment: "Detail of the Trash row; %lld is the number of files")
                : String(localized: "Size unknown without Full Disk Access", comment: "Detail of the Trash row"),
            size: measurement.rootReadable ? measurement.bytes : 0,
            removal: .emptyTrash
        )]
        if !measurement.rootReadable {
            output.notes.append(String(localized: "macOS lets 1Cleaner measure the Trash only with Full Disk Access. Empty Trash works without it.",
                                       comment: "Note in the Trash category; Empty Trash is the button's name"))
        }
        return [.trash: output]
    }
}

/// Browser cache folders (pages, images and scripts saved to load sites faster; never cookies, history or
/// passwords). Locked while that browser runs, since it keeps these files open.
struct BrowserCachesScanner: Scanner {
    /// Row title → the browser's bundle identifier.
    static let bundleIDs: [String: String] = [
        "Safari": "com.apple.Safari", "Google Chrome": "com.google.Chrome", "Chrome Canary": "com.google.Chrome.canary",
        "Chromium": "org.chromium.Chromium", "Microsoft Edge": "com.microsoft.edgemac", "Brave": "com.brave.Browser",
        "Arc": "company.thebrowser.Browser", "Firefox": "org.mozilla.firefox", "Opera": "com.operasoftware.Opera",
        "Vivaldi": "com.vivaldi.Vivaldi", "Yandex Browser": "ru.yandex.desktop.yandex-browser",
    ]

    var categories: [CategoryID] { [.browserCaches] }

    /// The running browser whose cache this path is, checked at the scan and again right before removal.
    static func runningOwner(of path: String) -> String? {
        let home = NSHomeDirectory() + "/"
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for location in KnownLocations.browsers {
            guard case .fixed(let title) = location.naming, let id = bundleIDs[title], running.contains(id),
                  location.paths.contains(where: { path == home + $0 || path.hasPrefix(home + $0 + "/") }) else { continue }
            return title
        }
        return nil
    }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        var output = await LocationScanner(category: .browserCaches, locations: KnownLocations.browsers).scan(context)[.browserCaches]
            ?? ScanOutput()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        output.items = output.items.map { item in
            var item = item
            if let id = Self.bundleIDs[item.title], running.contains(id) {
                item.lockedReason = String(localized: "Running. Quit \(item.title) to clean its cache.",
                                           comment: "Why a browser's cache row can't be selected; %@ is a browser name")
            }
            return item
        }
        return [.browserCaches: output]
    }
}

/// Editor caches, except those inside the data of an agent that's no longer installed (AI Agents offers that
/// whole folder), so a path never shows twice.
struct EditorsScanner: Scanner {
    var categories: [CategoryID] { [.editors] }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        var output = await LocationScanner(category: .editors, locations: KnownLocations.editors).scan(context)[.editors]
            ?? ScanOutput()
        let claimed = AgentsScanner.uninstalledAppSupportFolders(home: context.home)
            .map { context.homePath("Library/Application Support/" + $0) + "/" }
        output.items.removeAll { item in item.removal.paths.contains { path in claimed.contains { path.hasPrefix($0) } } }
        // A running editor uses its caches: locked until it quits.
        output.items = output.items.map { item in
            var item = item
            guard let path = item.removal.paths.first, let name = Self.runningOwner(of: path) else { return item }
            item.lockedReason = String(localized: "Running. Quit \(name) to clean its cache.",
                                       comment: "Why a browser's cache row can't be selected; %@ is a browser name")
            return item
        }
        return [.editors: output]
    }

    /// The name of the running editor that owns this cache path, checked at the scan and again before removal.
    static func runningOwner(of path: String) -> String? {
        let ids = owners.filter { path.contains($0.folder) }.map(\.id)
        guard !ids.isEmpty else { return nil }
        let editor = NSWorkspace.shared.runningApplications.first { app in
            guard let bundle = app.bundleIdentifier, bundle != "com.jetbrains.toolbox" else { return false }
            return ids.contains { $0.hasSuffix(".") ? bundle.hasPrefix($0) : bundle == $0 }
        }
        return editor.map { $0.localizedName ?? $0.bundleIdentifier ?? "" }
    }

    /// Cache folder → the editor's bundle identifier (a trailing dot: any app of that vendor).
    static let owners: [(folder: String, id: String)] = [
        ("/Library/Application Support/Code/", "com.microsoft.VSCode"),
        ("/Library/Application Support/Cursor/", "com.todesktop.230313mzl4w4u92"),
        ("/Library/Application Support/Windsurf/", "com.exafunction.windsurf"),
        ("/Library/Caches/JetBrains/", "com.jetbrains."),
        ("/Library/Caches/Zed", "dev.zed.Zed"),
    ]
}
