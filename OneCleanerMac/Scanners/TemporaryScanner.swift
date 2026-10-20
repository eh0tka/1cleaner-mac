import Darwin
import Foundation

/// Temporary files: the system /tmp and this user's macOS temp folder (items untouched for `systemDays`), and
/// temp folders the person keeps in the home folder (~/tmp, ~/temp; items untouched for `homeDays`).
///
/// "Untouched" means nothing anywhere inside changed, so running builds and agent sessions are never offered.
/// A recently changed folder isn't skipped whole: its old entries are listed up to two levels down (for example old
/// agent sessions in `claude-501/<project>/` next to the current one).
struct TemporaryScanner: Scanner {
    static let systemDays = 3
    static let homeDays = 30

    var categories: [CategoryID] { [.temporary] }

    /// Where temp items may go to the Trash outside the home folder (canonical paths, no /tmp or /var symlinks).
    static var systemRoots: [String] {
        var roots = [canonical("/private/tmp")]
        if let userTemp = userTempFolder { roots.append(userTemp) }
        return roots.compactMap { $0 }
    }

    /// This user's macOS temp folder (`/private/var/folders/…/T`).
    static var userTempFolder: String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return canonical(String(decoding: bytes, as: UTF8.self))
    }

    static func canonical(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        var rows: [[String]] = []
        for root in Self.systemRoots {
            rows += Self.oldEntries(in: root, days: Self.systemDays, now: context.now)
        }
        var seen = Set<String>()
        for name in ["tmp", "temp", "Temp", "TMP"] {
            // A link (`~/tmp` → `~/Documents`) would show the folder it leads to as temporary files.
            guard !FileInfo.isSymbolicLink(context.homePath(name)),
                  let root = Self.canonical(context.homePath(name)), FileInfo.isDirectory(root),
                  seen.insert(root.lowercased()).inserted else { continue }
            rows += Self.oldEntries(in: root, days: Self.homeDays, now: context.now)
        }
        let items: [CleanupItem?] = await Concurrency.map(rows) { paths -> CleanupItem? in
            var bytes: Int64 = 0
            var changed: Date?
            for path in paths {
                bytes += FileSizer.measure(path, progress: context.progress).bytes
                if let date = Self.newestChange(path) { changed = max(changed ?? date, date) }
            }
            // Offered because nobody touched them for days: something changed in the last day keeps them, and
            // anything changed since the scan.
            let targets = paths.compactMap(FileTarget.init(watching:)).map { target in
                var target = target
                target.quietForADay = true
                return target
            }
            guard bytes > 0, !targets.isEmpty, targets.count == paths.count, let first = paths.first else { return nil }
            let folder = (first as NSString).deletingLastPathComponent
            let home = first.hasPrefix(context.home + "/")
            // Something that changed while it was measured is in use: it isn't offered.
            let days = home ? Self.homeDays : Self.systemDays
            if let changed, changed > context.now.addingTimeInterval(-Double(days) * 86_400) { return nil }
            let lastChanged = changed.map {
                " · " + String(localized: "last changed \($0.relativeDescription)",
                               comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
            } ?? ""
            var item = CleanupItem(
                id: paths.count == 1 ? first : folder + "#oldfiles",
                category: .temporary,
                title: paths.count == 1 ? (first as NSString).lastPathComponent
                    : String(localized: "\(paths.count) old files in \((folder as NSString).lastPathComponent)",
                             comment: "Temporary Files row title; %lld is the number of files, %@ a folder name"),
                badge: home ? String(localized: "Your temp folder", comment: "Badge of an item in ~/tmp or a similar folder")
                    : String(localized: "System temp", comment: "Badge of an item in the system's temporary folders"),
                detail: PathDisplay.abbreviated(folder) + lastChanged,
                size: bytes,
                removal: .trash(targets),
                date: changed
            )
            if paths.count == 1, Self.isSimulatorDevice(first) {
                // A simulator device left by a test tool, named and Ask AI like Simulators.
                let info = NSDictionary(contentsOfFile: first + "/device.plist")
                let runtime = (info?["runtime"] as? String).map(SimulatorScanner.runtimeName)
                item = CleanupItem(
                    id: item.id, category: .temporary,
                    title: info?["name"] as? String
                        ?? String(localized: "Simulator device", comment: "Title or badge of a simulator device"),
                    badge: String(localized: "Simulator device", comment: "Title or badge of a simulator device"),
                    detail: [runtime, String(localized: "temporary device set in \(PathDisplay.abbreviated(folder))",
                                             comment: "Fact in a temporary simulator device's detail line; %@ is a folder path")]
                        .compactMap { $0 }.joined(separator: " · ") + lastChanged,
                    size: bytes, removal: item.removal,
                    // CoreSimulator state 3 = booted.
                    lockedReason: info?["state"] as? Int == 3
                        ? String(localized: "Running. Shut it down to remove it.", comment: "Why a running simulator device can't be selected")
                        : nil,
                    date: changed, safetyLevel: .askAI
                )
            } else if let claude = Self.claudeCodeTemp(first, home: context.home) {
                // A Claude Code session's scratchpad can hold the only copy of its work.
                item = CleanupItem(
                    id: item.id, category: .temporary, title: claude.title, badge: "Claude Code",
                    detail: claude.detail + lastChanged, size: bytes, removal: item.removal,
                    date: changed, safetyLevel: .askAI
                )
            }
            return item
        }
        var output = ScanOutput(items: items.compactMap { $0 }.sorted { $0.size > $1.size })
        output.summary = String(localized: """
            Shown: system temp items untouched for \(Self.systemDays)+ days (macOS also clears /tmp when it restarts) \
            and items in your own temp folders untouched for \(Self.homeDays)+ days.
            """, comment: "Summary above Temporary Files; first %lld is days for system temp, second %lld for the person's temp folders")
        return [.temporary: output]
    }

    /// Old entries of `root` owned by this user, as rows: an untouched entry is one row; a recently changed folder
    /// contributes its old subfolders as rows (up to two levels down) and its old loose files as one grouped row.
    static func oldEntries(in root: String, days: Int, now: Date) -> [[String]] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var rows: [[String]] = []
        func isOld(_ path: String) -> (old: Bool, isFolder: Bool)? {
            var info = stat()
            guard lstat(path, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) != S_IFLNK,
                  let changed = newestChange(path) else { return nil }
            return (changed < cutoff, (info.st_mode & S_IFMT) == S_IFDIR)
        }
        func descend(_ folder: String, depth: Int) {
            var looseFiles: [String] = []
            // macOS's own temp entries (com.apple.*, NSIRD_*) are managed by the system.
            for child in FileInfo.children(folder)
            where !child.hasPrefix(".") && !child.hasPrefix("com.apple.") && !child.hasPrefix("NSIRD_") {
                let path = folder + "/" + child
                guard let state = isOld(path) else { continue }
                let isDevice = state.isFolder && isSimulatorDevice(path)
                // A temporary device set: each old device is its own row, at any depth.
                if state.isFolder, !isDevice {
                    let devices = FileInfo.children(path).map { path + "/" + $0 }.filter(isSimulatorDevice)
                    if !devices.isEmpty {
                        for device in devices where isOld(device)?.old == true { rows.append([device]) }
                        continue
                    }
                }
                if state.old {
                    if state.isFolder { rows.append([path]) } else { looseFiles.append(path) }
                } else if state.isFolder, !isDevice, depth < 2 {
                    descend(path, depth: depth + 1)
                }
            }
            if !looseFiles.isEmpty { rows.append(looseFiles) }
        }
        descend(root, depth: 0)
        return rows
    }

    /// The newest file change anywhere inside (capped walk; a huge tree that isn't fully read counts as
    /// recent). A file's status change counts too: an archive unpacked today keeps its files' old modification
    /// dates, but not their change dates. Folder dates are ignored: removing something inside a folder changes its
    /// date, so a cleanup would look like use. A tree without files falls back to its folders' dates.
    static func newestChange(_ path: String) -> Date? {
        var newestFile: TimeInterval = 0
        var newestFolder: TimeInterval = 0
        var visited = 0
        var complete = true
        let whole = FileSizer.walk(path) { entry in
            visited += 1
            // A walk cut short or a folder that can't be read: the age is unknown, so it counts as just changed.
            let info = Int32(entry.pointee.fts_info)
            if visited > 200_000 || Task.isCancelled || info == FTS_DNR || info == FTS_ERR || info == FTS_NS {
                complete = false
                return .stop
            }
            if let stat = entry.pointee.fts_statp?.pointee {
                let time = TimeInterval(stat.st_mtimespec.tv_sec)
                if Int32(entry.pointee.fts_info) == FTS_D {
                    newestFolder = max(newestFolder, time)
                } else {
                    newestFile = max(newestFile, time, TimeInterval(stat.st_ctimespec.tv_sec))
                }
            }
            return .continue
        }
        // Not read through, or nothing read at all: the age is unknown, so it counts as just changed.
        guard complete, whole, visited > 0 else { return Date() }
        let newest = newestFile > 0 ? newestFile : newestFolder
        guard newest > 0 else { return nil }
        return Date(timeIntervalSince1970: newest)
    }

    /// Claude Code's temp folders: `/private/tmp/claude-<uid>[/<project>[/<session>]]`.
    static func claudeCodeTemp(_ path: String, home: String) -> (title: String, detail: String)? {
        let parts = path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(where: { $0.hasPrefix("claude-") && Int($0.dropFirst(7)) != nil }),
              index >= 1, parts[index - 1] == "tmp" else { return nil }
        let rest = parts[(index + 1)...]
        let root = "/" + parts[...index].joined(separator: "/")
        guard let project = rest.first, FileInfo.isDirectory(root + "/" + project) else {
            return (String(localized: "Claude Code temp files", comment: "Temporary Files row title"),
                    String(localized: "Scratchpads and task output of past sessions", comment: "Detail of Claude Code temp files"))
        }
        let name = AgentsScanner.projectName(project, home: home)
        if rest.count >= 2 {
            return (String(localized: "Claude Code session files · \(name)",
                           comment: "Temporary Files row title; %@ is a project path like ~/www/app"),
                    String(localized: "One past session's scratchpad and task output; it may hold work that isn't saved elsewhere",
                           comment: "Detail of one Claude Code session's temp files"))
        }
        return (String(localized: "Claude Code temp files · \(name)",
                       comment: "Temporary Files row title; %@ is a project path like ~/www/app"),
                String(localized: "Scratchpads and task output of this project's past sessions",
                       comment: "Detail of a project's Claude Code temp files"))
    }

    /// A simulator device folder (`<UDID>/device.plist` + `data`), e.g. from a test tool's temporary device set.
    static func isSimulatorDevice(_ path: String) -> Bool {
        FileInfo.exists(path + "/device.plist") && FileInfo.isDirectory(path + "/data")
    }
}
