import Darwin
import AppKit
import Foundation

/// Files in ~/Library left by apps that are no longer installed: real leftovers, unlike an installed app's data.
///
/// Conservative on purpose: only names that are bundle identifiers (`com.vendor.app`, three or more parts) are
/// considered, and an identifier counts as orphaned only when no installed app has it or extends it, LaunchServices
/// doesn't know it, nothing with it is running, no installed app shares its vendor (`com.vendor`), since
/// vendors keep updaters and helpers under other identifiers, and nothing of it changed in the last
/// `recentDays` days (something still writes there). A launch agent counts only when its program is gone.
/// Identifiers that extend another orphan (`com.vendor.app.widget`) are shown as part of it.
struct LeftoversScanner: Scanner {
    var categories: [CategoryID] { [.leftovers] }

    /// ~/Library folders where apps keep files named by their identifier. Caches and Logs are left out: the App
    /// Caches and Logs categories already list every folder there, so a path never shows twice.
    static let places = [
        "Application Support", "Preferences", "Saved Application State", "HTTPStorages", "WebKit", "Application Scripts",
    ]
    static let suffixes = [".plist", ".savedState", ".binarycookies", ".ShipIt"]
    static let recentDays = 30

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        let installed = Self.installedIdentifiers(home: context.home)
        let vendors = Set(installed.map(Self.vendor))
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        let library = context.home + "/Library/"
        var places = Self.places
        if context.fullDiskAccess { places.append("Containers") }

        var pathsByID: [String: [String]] = [:]
        for place in places {
            for name in FileInfo.children(library + place) where !name.hasPrefix(".") {
                guard let id = Self.identifier(from: name) else { continue }
                pathsByID[id, default: []].append(library + place + "/" + name)
            }
        }
        for name in FileInfo.children(library + "LaunchAgents") where name.hasSuffix(".plist") {
            let path = library + "LaunchAgents/" + name
            if let program = Self.launchAgentProgram(path), program.hasPrefix("/"), !FileInfo.exists(program),
               let id = Self.identifier(from: name) {
                pathsByID[id, default: []].append(path)
            }
        }

        let recent = context.now.addingTimeInterval(-Double(Self.recentDays) * 86_400)
        var orphans = pathsByID.filter { id, paths in
            if paths.contains(where: { (FileInfo.modificationDate($0) ?? .distantPast) > recent }) { return false }
            let lower = id.lowercased()
            guard !lower.hasPrefix("com.apple."), !KnownLocations.claimedCacheFolders.contains(id),
                  !running.contains(lower), !vendors.contains(Self.vendor(lower)) else { return false }
            if installed.contains(where: { lower == $0 || lower.hasPrefix($0 + ".") || $0.hasPrefix(lower + ".") }) {
                return false
            }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) == nil
        }
        // One row per app: fold extension and helper identifiers into the shortest orphan they extend.
        for id in orphans.keys.sorted(by: { $0.count > $1.count }) {
            let lower = id.lowercased()
            if let parent = orphans.keys.filter({ lower.hasPrefix($0.lowercased() + ".") }).min(by: { $0.count < $1.count }),
               let paths = orphans.removeValue(forKey: id) {
                orphans[parent, default: []] += paths
            }
        }

        let items: [CleanupItem?] = await Concurrency.map(Array(orphans), limit: 4) { entry -> CleanupItem? in
            let (id, paths) = entry
            var bytes: Int64 = 0
            var newest: Date?
            for path in paths {
                let measurement = FileSizer.measure(path, progress: context.progress)
                // A folder's own date doesn't change when a file deep inside does: anything changed inside within
                // `recentDays` keeps the app's data out of the list, and so does a part that couldn't be read through
                // (its age is unknown).
                guard measurement.latestChangeDate <= recent, measurement.unreadable == 0, !Task.isCancelled else {
                    return nil
                }
                bytes += measurement.bytes
                newest = max(newest ?? measurement.latestChangeDate, measurement.latestChangeDate)
            }
            // Watched file by file: something saved into it after the scan (the app installed again) keeps it.
            let targets = paths.compactMap(FileTarget.init(watching:))
            guard !targets.isEmpty, targets.count == paths.count else { return nil }
            let userData = Self.userDataSigns(in: paths)
            return CleanupItem(
                id: "leftovers:" + id,
                category: .leftovers,
                title: Self.displayName(for: id),
                badge: paths.count == 1 ? nil
                    : String(localized: "\(paths.count) places",
                             comment: "Badge of a leftovers row; %lld is the number of places in ~/Library"),
                detail: id + (newest.map {
                    " · " + String(localized: "last changed \($0.relativeDescription)",
                                   comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
                } ?? "")
                    + " · " + (userData.isEmpty
                        ? String(localized: "settings and caches only", comment: "Fact in a leftovers row's detail line")
                        : String(localized: "has \(userData.joined(separator: ", "))",
                                 comment: "Fact in a leftovers row's detail line; %@ is a list like 'saved passwords, bookmarks'")),
                size: bytes,
                removal: .trash(targets),
                date: newest,
                userData: userData
            )
        }
        return [.leftovers: ScanOutput(items: items.compactMap { $0 }.sorted { $0.size > $1.size })]
    }

    /// Cookies and website storage of an app that's gone are only old sign-ins, so they don't count.
    static let userDataNames: [String: String] = [
        "Login Data": String(localized: "saved passwords", comment: "Kind of personal data found in a leftover, in a list"),
        "Bookmarks": String(localized: "bookmarks", comment: "Kind of personal data found in a leftover, in a list"),
        "History": String(localized: "browsing history", comment: "Kind of personal data found in a leftover, in a list"),
    ]
    static let documentsSign = String(localized: "documents", comment: "Kind of personal data found in a leftover, in a list")
    static let databasesSign = String(localized: "databases", comment: "Kind of personal data found in a leftover, in a list")
    static let minimumDatabase = 512 * 1024
    static let databaseExtensions: Set<String> = ["sqlite", "sqlite3", "db", "realm", "storedata", "kdbx", "wallet"]

    /// What in Application Support or an app container looks like the person's data rather than settings or
    /// caches. Preferences, saved window state, HTTP and WebKit storage of a removed app are settings and caches.
    static func userDataSigns(in paths: [String]) -> [String] {
        var signs: [String] = []
        for path in paths where path.contains("/Library/Application Support/") || path.contains("/Library/Containers/") {
            var visited = 0
            FileSizer.walk(path) { entry in
                visited += 1
                if visited > 20_000 || Task.isCancelled { return .stop }
                let name = entry.name
                if WebCache.folderNames.contains(name) { return .skip }
                if let sign = userDataNames[name], !signs.contains(sign) { signs.append(sign) }
                // Sandboxed apps all have an (often empty) Documents folder; only files in it count.
                if name == "Documents", Int32(entry.pointee.fts_info) == FTS_D {
                    if !signs.contains(documentsSign), FileSizer.measure(entry.path).logicalBytes > 4096 {
                        signs.append(documentsSign)
                    }
                    return .skip
                }
                if Int32(entry.pointee.fts_info) == FTS_F,
                   databaseExtensions.contains((name as NSString).pathExtension.lowercased()),
                   let stat = entry.pointee.fts_statp?.pointee, stat.st_size > minimumDatabase,
                   !signs.contains(databasesSign) {
                    signs.append(databasesSign)
                }
                return .continue
            }
        }
        return signs
    }

    /// `com.vendor.app.plist` → `com.vendor.app`; nil for names that aren't bundle identifiers.
    static func identifier(from name: String) -> String? {
        var id = name
        for suffix in suffixes where id.hasSuffix(suffix) { id = String(id.dropLast(suffix.count)) }
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }),
              id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }),
              parts[0].allSatisfy({ $0.isLowercase && $0.isLetter }), parts[0] != "group" else { return nil }
        return id
    }

    /// `com.vendor` from `com.vendor.app`; on code hosts the account is the vendor (`io.github.someone`), or one
    /// installed app from GitHub would hide every other's leftovers.
    static func vendor(_ id: String) -> String {
        let parts = id.lowercased().split(separator: ".")
        let host = parts.prefix(2).joined(separator: ".")
        let hosting: Set<String> = ["io.github", "com.github", "io.gitlab", "com.gitlab", "org.freedesktop", "org.kde",
                                    "org.gnome", "net.sourceforge", "com.sourceforge", "io.codeberg", "org.codeberg"]
        return parts.prefix(hosting.contains(host) ? 3 : 2).joined(separator: ".")
    }

    /// Lowercased identifiers of every app on this Mac: /Applications, ~/Applications and Apple's folders, two levels
    /// deep, plus apps nested inside apps (helpers, login items).
    static func installedIdentifiers(home: String) -> Set<String> {
        var ids = Set<String>()
        let roots = ["/Applications", home + "/Applications", "/System/Applications", "/System/Library/CoreServices"]
        func collect(_ appPath: String, depth: Int) {
            if let info = NSDictionary(contentsOfFile: appPath + "/Contents/Info.plist"),
               let id = info["CFBundleIdentifier"] as? String {
                ids.insert(id.lowercased())
            }
            guard depth < 2 else { return }
            for sub in ["Contents/Library/LoginItems", "Contents/Helpers", "Contents/Frameworks", "Contents/Applications"] {
                for name in FileInfo.children(appPath + "/" + sub) where name.hasSuffix(".app") {
                    collect(appPath + "/" + sub + "/" + name, depth: depth + 1)
                }
            }
        }
        for root in roots {
            for name in FileInfo.children(root) {
                let path = root + "/" + name
                if name.hasSuffix(".app") {
                    collect(path, depth: 0)
                } else if FileInfo.isDirectory(path) {
                    for inner in FileInfo.children(path) where inner.hasSuffix(".app") {
                        collect(path + "/" + inner, depth: 0)
                    }
                }
            }
        }
        return ids
    }

    /// The program a launch agent starts.
    static func launchAgentProgram(_ path: String) -> String? {
        guard let plist = NSDictionary(contentsOfFile: path) else { return nil }
        if let program = plist["Program"] as? String { return program }
        return (plist["ProgramArguments"] as? [String])?.first
    }

    /// `com.vendor.my-app` → "My App (com.vendor)".
    static func displayName(for id: String) -> String {
        let parts = id.split(separator: ".")
        guard let last = parts.last else { return id }
        let words = last.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        let name = words.prefix(1).uppercased() + words.dropFirst()
        return name + " (" + parts.prefix(2).joined(separator: ".") + ")"
    }
}

/// Chromium/Electron cache folder names: rebuilt by the app, never the person's data.
enum WebCache {
    static let folderNames: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "GraphiteDawnCache",
        "ShaderCache", "GrShaderCache", "Service Worker", "component_crx_cache", "extensions_crx_cache", "Caches",
    ]
}
