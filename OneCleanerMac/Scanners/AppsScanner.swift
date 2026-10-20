import AppKit
import CoreServices
import Darwin
import Foundation
import Security

/// Installed apps with their leftovers in ~/Library, for uninstalling: the app and its own data go to the Trash
/// together. Leftovers are matched by the app's bundle identifier (and exact app name for the few folders apps
/// name after themselves), never by partial names. Apple apps, Xcode (see the Xcode category), 1Cleaner itself
/// and running apps are not offered.
struct AppsScanner: Scanner {
    var categories: [CategoryID] { [.apps] }

    struct App: Sendable {
        let path: String
        let bundleID: String
        let name: String
        let version: String?
    }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let apps = Self.installedApps(home: context.home)
        // App groups each app declares; a group that more than one installed app declares (Office, a vendor's
        // suite) is shared data and stays when one of them is removed.
        let groups: [String: [String]] = context.fullDiskAccess
            ? Dictionary(apps.map { ($0.bundleID, Self.appGroups(of: $0.path)) }, uniquingKeysWith: { first, _ in first })
            : [:]
        // Who uses a group counts the apps' extensions and helpers too: a group the app declares that only another
        // app's extension declares is shared all the same. What is removed with an app stays its own groups.
        let usedGroups: [String: Set<String>] = context.fullDiskAccess
            ? Dictionary(apps.map { app in
                (app.bundleID, Set(Self.appGroups(of: app.path) + Self.nestedCode(of: app.path).flatMap(Self.appGroups(of:))))
            }, uniquingKeysWith: { $0.union($1) })
            : [:]
        var groupUsers: [String: Int] = [:]
        for list in usedGroups.values { for group in list { groupUsers[group, default: 0] += 1 } }
        let sharedGroups = Set(groupUsers.filter { $0.value > 1 }.keys)
        let allIDs = Set(apps.map(\.bundleID))
        // Two copies of one app (/Applications and ~/Applications, an old version) share their ~/Library data:
        // removing one copy takes only its bundle, the data stays for the other.
        let copies = Dictionary(apps.map { ($0.bundleID, 1) }, uniquingKeysWith: +)
        // Every app on the Mac, Apple's included, for "a folder named like this app may be another app's".
        let everyApp = Self.installedApps(home: context.home, everything: true)
        let items: [CleanupItem?] = await Concurrency.map(apps, limit: 3) { app -> CleanupItem? in
            let appSize = FileSizer.measure(app.path, progress: context.progress)
            guard appSize.rootReadable, let appTarget = FileTarget(path: app.path) else { return nil }
            let others = everyApp.filter { $0.bundleID != app.bundleID }
            let onlyCopy = copies[app.bundleID, default: 1] == 1
            let leftovers = !onlyCopy ? [] : Self.leftovers(
                of: app, home: context.home, fullDiskAccess: context.fullDiskAccess,
                groups: (groups[app.bundleID] ?? []).filter { !sharedGroups.contains($0) },
                sharedGroups: sharedGroups, otherIDs: allIDs.union(everyApp.map(\.bundleID)).subtracting([app.bundleID]), otherApps: others
            )
            // Folders named after the app that another app may own stay, and the row says so.
            let nameOwner = Self.nameOwner(of: app, among: others)
            let keptFolders = nameOwner == nil || !onlyCopy
                ? [] : Self.nameFolders(of: app, home: context.home).filter(FileInfo.exists)
            var leftoverBytes: Int64 = 0
            for path in leftovers { leftoverBytes += FileSizer.measure(path).bytes }
            let lastOpened = ProjectScanner.lastOpened(app.path)
            // While the app is installed its data is its working data (settings, history, logins), not junk.
            var detail = leftovers.isEmpty
                ? String(localized: "App \(appSize.bytes.formattedBytes)",
                         comment: "Uninstaller row detail; %@ is the app's size like '1.2 GB'")
                : String(localized: """
                    App \(appSize.bytes.formattedBytes) + app data \(leftoverBytes.formattedBytes) in \(leftovers.count) places
                    """, comment: "Uninstaller row detail; first %@ is the app's size, second %@ its data size, %lld the number of places")
            detail += " · " + (lastOpened.map {
                String(localized: "opened \($0.relativeDescription)",
                       comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
            } ?? String(localized: "never opened", comment: "Fact in a row's detail line: the app or file was never opened"))
            if let nameOwner, let kept = keptFolders.first {
                let folder = (kept as NSString).lastPathComponent
                detail += " · " + String(localized: "“\(folder)” folder stays: it may belong to \(nameOwner.name)",
                                         comment: "Fact in an uninstaller row's detail line; first %@ is a folder name, second %@ another app's name")
            }
            return CleanupItem(
                id: app.path,
                category: .apps,
                title: app.name + (app.version.map { " \($0)" } ?? ""),
                badge: app.path.hasPrefix(context.home)
                    ? String(localized: "Your apps", comment: "Badge of an app installed in ~/Applications") : nil,
                detail: detail,
                size: appSize.bytes + leftoverBytes,
                // Its data stays while any copy of the app runs, also one started from elsewhere after the scan.
                removal: .trash([appTarget] + leftovers.compactMap(FileTarget.init(path:)).map { target in
                    var target = target
                    target.usedWhileRunning = [app.bundleID]
                    return target
                }),
                lockedReason: running.contains(app.bundleID)
                    ? String(localized: "Running. Quit it to remove it.", comment: "Why a running app can't be selected") : nil,
                date: lastOpened
            )
        }
        var output = ScanOutput(items: items.compactMap { $0 }.sorted { $0.size > $1.size })
        if !context.fullDiskAccess {
            output.notes.append(String(localized: """
                Without Full Disk Access, the data of App Store apps (their containers) isn't listed as leftovers.
                """, comment: "Note above the Apps list"))
        }
        return [.apps: output]
    }

    /// Apps in /Applications and ~/Applications, top level and one folder deep (e.g. /Applications/Setapp).
    /// `everything` also lists Apple's apps (and /System/Applications), Xcode and 1Cleaner, which are never offered
    /// but may own folders named after them.
    static func installedApps(home: String, everything: Bool = false) -> [App] {
        let ownID = Bundle.main.bundleIdentifier ?? ""
        var paths: [String] = []
        for root in ["/Applications", home + "/Applications"] + (everything ? ["/System/Applications"] : []) {
            for name in FileInfo.children(root) where !name.hasPrefix(".") {
                let path = root + "/" + name
                if name.hasSuffix(".app") {
                    paths.append(path)
                } else if FileInfo.isDirectory(path) {
                    paths += FileInfo.children(path).filter { $0.hasSuffix(".app") }.map { path + "/" + $0 }
                }
            }
        }
        return paths.compactMap { path in
            guard let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist"),
                  let bundleID = info["CFBundleIdentifier"] as? String,
                  everything || (!bundleID.hasPrefix("com.apple.") && bundleID != ownID
                      && !(path as NSString).lastPathComponent.hasPrefix("Xcode")) else { return nil }
            let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
                ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            return App(path: path, bundleID: bundleID, name: name,
                       version: info["CFBundleShortVersionString"] as? String)
        }
    }

    /// `group.net.whatsapp.WhatsApp.shared` or `6N38VWS5BX.ru.keepcoder.Telegram` for the app `ru.keepcoder.Telegram`.
    static func groupNameMatches(_ name: String, id: String) -> Bool {
        let bare = AppCachesScanner.appID(ofGroup: name)
        return bare == id || bare.hasPrefix(id + ".")
    }

    /// The app groups (`com.apple.security.application-groups`) in the app's code signature.
    static func appGroups(of path: String) -> [String] {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return [] }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation)
        guard SecCodeCopySigningInformation(code, flags, &info) == errSecSuccess,
              let entitlements = (info as? [String: Any])?[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }

    /// Code inside an app with entitlements of its own: extensions, login items, system extensions, XPC services,
    /// helper apps (also Electron's in Frameworks) and helper programs, and the same inside those, a few levels down.
    static func nestedCode(of bundle: String, depth: Int = 0) -> [String] {
        guard depth < 3 else { return [] }
        let contents = bundle + "/Contents/"
        let suffixes = [".appex", ".app", ".xpc", ".systemextension"]
        var found: [String] = []
        for folder in ["PlugIns", "Extensions", "Library/LoginItems", "Library/SystemExtensions", "Library/LaunchServices",
                       "XPCServices", "Helpers", "Library/Helpers", "MacOS", "Frameworks"] {
            for name in FileInfo.children(contents + folder) {
                let path = contents + folder + "/" + name
                if suffixes.contains(where: { name.hasSuffix($0) }) {
                    found.append(path)
                    found += nestedCode(of: path, depth: depth + 1)
                } else if folder != "Frameworks", !name.contains("."), isProgram(path) {
                    found.append(path)
                }
            }
        }
        return found
    }

    /// A regular file anyone may run: a helper program, whose signature can hold entitlements.
    private static func isProgram(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG && (info.st_mode & 0o111) != 0
    }

    static func isReverseDNS(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
    }

    /// Folders some apps name after themselves (`Application Support/Slack`), only for distinctive names.
    static func nameFolders(of app: App, home: String) -> [String] {
        let fileName = ((app.path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard fileName.count >= 4 else { return [] }
        return ["Application Support/", "Caches/", "Logs/"].map { home + "/Library/" + $0 + fileName }
    }

    /// Another installed app whose name or bundle id contains this app's file name: the folders named after it may be
    /// that app's data (`Code.app` and Visual Studio Code's `Application Support/Code`).
    static func nameOwner(of app: App, among others: [App]) -> App? {
        let fileName = ((app.path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard fileName.count >= 4 else { return nil }
        let name = words(fileName)
        // Whole words in order: "Code" is in "Visual Studio Code" and com.microsoft.VSCode, not in Xcode.
        func contains(_ text: String) -> Bool {
            let all = words(text)
            guard all.count >= name.count else { return false }
            return (0...(all.count - name.count)).contains { Array(all[$0..<($0 + name.count)]) == name }
        }
        return others.first { other in
            let otherFile = ((other.path as NSString).lastPathComponent as NSString).deletingPathExtension
            return contains(other.name) || contains(other.bundleID) || contains(otherFile)
        }
    }

    /// "Visual Studio Code" → visual, studio, code; "com.microsoft.VSCode" → com, microsoft, vs, code.
    static func words(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previous: Character?
        for character in text {
            if !(character.isLetter || character.isNumber) {
                if !current.isEmpty { result.append(current) }
                current = ""
            } else {
                // A new word starts at a capital after a lowercase letter or digit (VSCode → VS, Code).
                if character.isUppercase, let previous, previous.isLowercase || previous.isNumber, !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { result.append(current) }
        // "VSCode": the capital run before a capitalized word belongs apart (VS, Code).
        return result.flatMap(splitCapitalRun).map { $0.lowercased() }
    }

    private static func splitCapitalRun(_ word: String) -> [String] {
        let characters = Array(word)
        guard characters.count > 2, let index = characters.indices.dropFirst().first(where: { i in
            characters[i].isUppercase && i + 1 < characters.count && characters[i + 1].isLowercase
                && characters[i - 1].isUppercase
        }) else { return [word] }
        return [String(characters[..<index])] + splitCapitalRun(String(characters[index...]))
    }

    /// The app's own files in ~/Library that exist right now. With Full Disk Access also its app groups, the
    /// group folders named after its bundle id, and its extensions' containers; never a group
    /// another installed app declares, never another app's container, never iCloud or file-sync data.
    static func leftovers(
        of app: App, home: String, fullDiskAccess: Bool,
        groups: [String] = [], sharedGroups: Set<String> = [], otherIDs: Set<String> = [], otherApps: [App] = []
    ) -> [String] {
        // An identifier like `Google` would name a whole vendor folder: only `com.vendor.app` identifies an app's data.
        guard isReverseDNS(app.bundleID) else { return [] }
        let library = home + "/Library/"
        let id = app.bundleID
        let fileName = ((app.path as NSString).lastPathComponent as NSString).deletingPathExtension
        var candidates = [
            "Application Support/\(id)", "Caches/\(id)", "Preferences/\(id).plist", "Saved Application State/\(id).savedState",
            "HTTPStorages/\(id)", "HTTPStorages/\(id).binarycookies", "WebKit/\(id)", "Logs/\(id)",
            "Application Scripts/\(id)",
        ]
        // Folders apps name after themselves, only for distinctive names nobody else installed shares.
        if fileName.count >= 4, nameOwner(of: app, among: otherApps) == nil {
            candidates += ["Application Support/\(fileName)", "Caches/\(fileName)", "Logs/\(fileName)"]
        }
        candidates.append("Cookies/\(id).binarycookies")
        // `com.vendor.App.Helper` belongs to an installed app `com.vendor.App.Helper`, not to `com.vendor.App`.
        func ownedByAnotherApp(_ bareID: String) -> Bool {
            otherIDs.contains { other in other.count > id.count && (bareID == other || bareID.hasPrefix(other + ".")) }
        }
        if fullDiskAccess {
            candidates.append("Containers/\(id)")
            // Extensions (widgets, share and Finder extensions) have ids under the app's own.
            candidates += FileInfo.children(library + "Containers")
                .filter { $0.hasPrefix(id + ".") && !ownedByAnotherApp($0) }
                .map { "Containers/" + $0 }
            // A group it declares but named after another installed app (the most specific id it's named after)
            // is that app's, even when only that app's extension declares it.
            candidates += groups.filter { group in
                let owner = otherIDs.union([id]).filter { Self.groupNameMatches(group, id: $0) }.max { $0.count < $1.count }
                return owner == nil || owner == id
            }.map { "Group Containers/" + $0 }
            // Group folders named after the bundle id: `group.<id>…` or `<TeamID>.<id>…`.
            candidates += FileInfo.children(library + "Group Containers").filter { name in
                guard !sharedGroups.contains(name), !groups.contains(name) else { return false }
                return Self.groupNameMatches(name, id: id) && !ownedByAnotherApp(AppCachesScanner.appID(ofGroup: name))
            }.map { "Group Containers/" + $0 }
        }
        var paths = candidates.map { library + $0 }.filter(FileInfo.exists).filter { !KnownLocations.isSyncServiceData($0) }
        paths += FileInfo.children(library + "Preferences/ByHost")
            .filter { $0.hasPrefix(id + ".") && $0.hasSuffix(".plist") && !ownedByAnotherApp(String($0.dropLast(".plist".count))) }
            .map { library + "Preferences/ByHost/" + $0 }
        // `com.vendor.App.plist` or `com.vendor.App.helper.plist`, never `com.vendor.App2.plist` or an agent of
        // another installed app `com.vendor.App.Helper`.
        paths += FileInfo.children(library + "LaunchAgents")
            .filter { name in
                guard name.hasSuffix(".plist") else { return false }
                let bare = String(name.dropLast(".plist".count))
                return bare == id || (bare.hasPrefix(id + ".") && !ownedByAnotherApp(bare))
            }
            .map { library + "LaunchAgents/" + $0 }
        // Case-insensitive disks can return the same folder twice through id and name.
        var seen = Set<String>()
        return paths.filter { seen.insert($0.lowercased()).inserted }
    }
}
