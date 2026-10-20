import AppKit
import Darwin
import Foundation

/// A known place on disk relative to the home folder. `*` in a path component matches like the shell.
struct Location: Sendable {
    enum Naming: Sendable {
        /// The given title.
        case fixed(String)
        /// "<prefix><file name>", e.g. "Gradle " + "gradle-8.7-bin".
        case name(prefix: String)
        /// "<parent folder> <file name>", e.g. "iOS DeviceSupport" + "18.2 (22C152)".
        case parentAndName
        /// An app name from a bundle-identifier folder such as `com.google.Chrome`.
        case appName
        /// A DerivedData folder: project name, with the workspace path read from its info.plist.
        case derivedData
        /// An `.xcarchive`: archive name and its date folder.
        case archive
        /// `system-images/android-34/google_apis/arm64-v8a`.
        case systemImage
        /// `models--meta-llama--Llama-3.1-8B` → "meta-llama/Llama-3.1-8B".
        case huggingFace
    }

    let paths: [String]
    let naming: Naming
    /// Each child of the matched folder is its own item.
    var perChild = false
    var detail: String?

    init(_ paths: String..., naming: Naming, perChild: Bool = false, detail: String? = nil) {
        self.paths = paths
        self.naming = naming
        self.perChild = perChild
        self.detail = detail
    }
}

struct LocationScanner: Scanner {
    let category: CategoryID
    let locations: [Location]

    var categories: [CategoryID] { [category] }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        let candidates = Self.candidates(for: locations, context: context)
        let items = await Self.measure(candidates, category: category, context: context)
        var output = ScanOutput(items: items.sorted { $0.size > $1.size })
        if candidates.contains(where: { $0.unreadable }) {
            output.notes.append(String(localized: "Some folders couldn't be read. Give 1Cleaner Full Disk Access in Settings to include them.",
                                       comment: "Note above a list when some known folders couldn't be read"))
        }
        return [category: output]
    }

    struct Candidate: Sendable {
        let paths: [String]
        let title: String
        let detail: String
        var unreadable = false
    }

    static func candidates(for locations: [Location], context: ScanContext) -> [Candidate] {
        var result: [Candidate] = []
        for location in locations {
            if location.paths.count > 1 {
                // Several folders that form one item, e.g. VS Code's cache folders.
                let existing = location.paths.map(context.homePath).filter(FileInfo.exists)
                guard !existing.isEmpty else { continue }
                result.append(Candidate(
                    paths: existing,
                    title: title(for: existing[0], naming: location.naming),
                    detail: location.detail ?? PathDisplay.abbreviated((existing[0] as NSString).deletingLastPathComponent)
                ))
                continue
            }
            for match in expand(context.homePath(location.paths[0])) {
                let paths = location.perChild
                    ? FileInfo.children(match).filter { !$0.hasPrefix(".") }.map { match + "/" + $0 }
                    : [match]
                for path in paths {
                    var detail = detail(for: path, naming: location.naming, fallback: location.detail)
                    if FileInfo.exists(path + "/LocalHistory") {
                        detail += " · " + String(localized: "holds Local History, the IDE's earlier versions of your files",
                                                 comment: "Fact in a JetBrains or Android Studio cache row's detail line")
                    }
                    result.append(Candidate(
                        paths: [path],
                        title: title(for: path, naming: location.naming),
                        detail: detail
                    ))
                }
            }
        }
        return result
    }

    static func measure(_ candidates: [Candidate], category: CategoryID, context: ScanContext) async -> [CleanupItem] {
        let measured: [CleanupItem?] = await Concurrency.map(candidates) { candidate -> CleanupItem? in
            var bytes: Int64 = 0
            var readable = false
            var newest: Date?
            for path in candidate.paths {
                let measurement = FileSizer.measure(path, progress: context.progress)
                bytes += measurement.bytes
                readable = readable || measurement.rootReadable
                if let date = FileInfo.modificationDate(path) { newest = max(newest ?? date, date) }
            }
            guard readable, bytes >= ScanContext.minimumItemSize else { return nil }
            let targets = candidate.paths.compactMap(FileTarget.init(path:))
            guard !targets.isEmpty else { return nil }
            return CleanupItem(
                id: candidate.paths[0],
                category: category,
                title: candidate.title,
                detail: candidate.detail,
                size: bytes,
                removal: .trash(targets),
                date: newest
            )
        }
        return measured.compactMap { $0 }
    }

    /// Expands `*` components; returns only paths that exist.
    static func expand(_ pattern: String) -> [String] {
        let components = pattern.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var current = [""]
        for component in components {
            var next: [String] = []
            for base in current {
                if component.contains("*") {
                    for child in FileInfo.children(base.isEmpty ? "/" : base)
                    where fnmatch(component, child, 0) == 0 && !child.hasPrefix(".") {
                        next.append(base + "/" + child)
                    }
                } else {
                    next.append(base + "/" + component)
                }
            }
            current = next
        }
        return current.filter(FileInfo.exists)
    }

    static func title(for path: String, naming: Location.Naming) -> String {
        let name = (path as NSString).lastPathComponent
        switch naming {
        case .fixed(let title):
            return title
        case .name(let prefix):
            return prefix + name
        case .parentAndName:
            return ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent + " · " + name
        case .appName:
            return AppNames.name(forFolder: name)
        case .derivedData:
            // "OneCleaner-abcdefghijklmnop" → "OneCleaner"
            if let dash = name.lastIndex(of: "-"), name.distance(from: dash, to: name.endIndex) > 20 {
                return String(name[..<dash])
            }
            return name
        case .archive:
            return (name as NSString).deletingPathExtension
        case .huggingFace:
            let parts = name.components(separatedBy: "--")
            guard parts.count >= 3 else { return name }
            return parts.dropFirst().joined(separator: "/")
        case .systemImage:
            let parts = path.split(separator: "/").suffix(3).map(String.init)
            guard parts.count == 3 else { return name }
            let api = parts[0].replacingOccurrences(of: "android-", with: "Android ")
            return "\(api) · \(parts[1].replacingOccurrences(of: "_", with: " ")) · \(parts[2])"
        }
    }

    static func detail(for path: String, naming: Location.Naming, fallback: String?) -> String {
        switch naming {
        case .derivedData:
            if let info = NSDictionary(contentsOfFile: path + "/info.plist"),
               let workspace = info["WorkspacePath"] as? String {
                let exists = FileInfo.exists(workspace)
                return PathDisplay.abbreviated(workspace)
                    + (exists ? "" : " · " + String(localized: "project no longer exists",
                                                     comment: "Fact in a DerivedData row's detail line"))
            }
        case .archive:
            if let date = FileInfo.modificationDate(path) {
                return String(localized: "Archived \(date.formatted(date: .abbreviated, time: .omitted))",
                              comment: "Xcode archive row detail; %@ is a date")
            }
        default:
            break
        }
        return fallback ?? PathDisplay.abbreviated(path)
    }
}

/// App names for bundle-identifier folders in Caches and Logs.
enum AppNames {
    static func name(forFolder folder: String) -> String {
        guard folder.contains("."), !folder.contains(" "),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: folder) else { return folder }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
