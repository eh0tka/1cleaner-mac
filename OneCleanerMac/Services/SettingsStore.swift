import Foundation
import Observation

/// Scan folders and the Safe List, kept in UserDefaults.
@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let roots = "scanRoots"
        /// Kept from the first build's "Never show this" list; same meaning.
        static let safeItems = "ignoredItems"
        static let safeFolders = "safeFolders"
        static let safeItemInfo = "safeItemInfo"
    }

    /// What a Safe List item was when it was added, so the Safe List can show it without a scan.
    struct SafeItemInfo: Codable, Sendable {
        var title: String
        var category: String
        var detail: String
        var path: String?
        /// Every path the item removes (an app with its data); missing for items added before 1.3.0.
        var paths: [String]?
        var size: Int64
        var added: Date

        var categoryID: CategoryID? { CategoryID(rawValue: category) }
    }

    private let defaults: UserDefaults

    /// Folders searched for project builds and large files. Default: the home folder.
    var scanRoots: [String] {
        didSet { defaults.set(scanRoots, forKey: Key.roots) }
    }

    /// Safe List items: IDs (paths or tool identifiers) that scans never show.
    var safeItems: [String] {
        didSet {
            defaults.set(safeItems, forKey: Key.safeItems)
            protectedCache = nil
        }
    }

    /// Safe List folders: nothing inside them is ever shown, and the project walk doesn't enter them.
    var safeFolders: [String] {
        didSet {
            defaults.set(safeFolders, forKey: Key.safeFolders)
            protectedCache = nil
        }
    }

    /// Descriptions of `safeItems` by ID. Items added by older builds have none.
    private(set) var safeItemInfo: [String: SafeItemInfo] {
        didSet {
            if let data = try? JSONEncoder().encode(safeItemInfo) { defaults.set(data, forKey: Key.safeItemInfo) }
            protectedCache = nil
        }
    }

    /// Every protected path, built once per Safe List change: `isSafe` runs for every item of every scan.
    @ObservationIgnored private var protectedCache: [String]?

    private var protectedPaths: [String] {
        if let protectedCache { return protectedCache }
        // Items saved by older builds without paths: their id is their path when it is one.
        let paths = safeFolders + safeItems.flatMap { id in
            safeItemInfo[id].flatMap { $0.paths ?? $0.path.map { [$0] } } ?? (id.hasPrefix("/") ? [id] : [])
        }
        protectedCache = paths
        return paths
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let roots = defaults.stringArray(forKey: Key.roots) ?? []
        scanRoots = roots.isEmpty ? [NSHomeDirectory()] : roots
        safeItems = defaults.stringArray(forKey: Key.safeItems) ?? []
        safeFolders = defaults.stringArray(forKey: Key.safeFolders) ?? []
        safeItemInfo = defaults.data(forKey: Key.safeItemInfo)
            .flatMap { try? JSONDecoder().decode([String: SafeItemInfo].self, from: $0) } ?? [:]
    }

    func addRoot(_ path: String) {
        guard !scanRoots.contains(path) else { return }
        scanRoots.append(path)
    }

    func removeRoot(_ path: String) {
        scanRoots.removeAll { $0 == path }
        if scanRoots.isEmpty { scanRoots = [NSHomeDirectory()] }
    }

    func addSafeItem(_ item: CleanupItem) {
        guard !safeItems.contains(item.id) else { return }
        safeItems.append(item.id)
        safeItemInfo[item.id] = SafeItemInfo(
            title: item.title, category: item.category.rawValue, detail: item.detail, path: item.revealPath,
            // An app kept is its bundle: its caches and logs stay cleanable in their own categories.
            paths: item.category == .apps ? [item.revealPath].compactMap { $0 } : item.removal.paths,
            size: item.size, added: Date()
        )
    }

    func removeSafeItem(_ id: String) {
        safeItems.removeAll { $0 == id }
        safeItemInfo[id] = nil
    }

    func addSafeFolder(_ path: String) {
        let path = (path as NSString).standardizingPath
        // The home folder or the disk itself would hide every scan.
        guard !safeFolders.contains(path), path != NSHomeDirectory(), path != "/" else { return }
        safeFolders.append(path)
    }

    func removeSafeFolder(_ path: String) {
        safeFolders.removeAll { $0 == path }
    }

    /// True when the item or any of its paths is on the Safe List, or one of its paths would take something on the
    /// Safe List with it (a protected folder inside an old download, a protected cache inside an app's data).
    func isSafe(_ item: CleanupItem) -> Bool {
        if safeItems.contains(item.id) { return true }
        let protected = protectedPaths
        let inside = (item.removal.paths + [item.projectPath].compactMap { $0 }).contains { path in
            protected.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
        return inside || item.removal.paths.contains { path in protected.contains { $0.hasPrefix(path + "/") } }
    }
}
