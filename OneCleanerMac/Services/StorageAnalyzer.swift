import Darwin
import Foundation
import SwiftUI

/// What kind of data takes the space, like macOS's own storage overview.
enum StorageBucket: String, CaseIterable, Codable, Identifiable, Sendable {
    case apps, developer, photos, videos, music, documents, archives, deviceBackups, mail, appData, trash, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: String(localized: "Applications", comment: "Storage kind: installed apps")
        case .developer: String(localized: "Developer", comment: "Storage kind: developer tools and caches")
        case .photos: String(localized: "Photos", comment: "Storage kind: photos and images")
        case .videos: String(localized: "Videos", comment: "Storage kind: video files")
        case .music: String(localized: "Music & Audio", comment: "Storage kind: music and other audio files")
        case .documents: String(localized: "Documents", comment: "Storage kind: documents (PDF, Word, text, ...)")
        case .archives: String(localized: "Archives & Disk Images", comment: "Storage kind: zip, dmg, pkg, ...")
        case .deviceBackups: String(localized: "iPhone & iPad Backups", comment: "Storage kind: device backups")
        case .mail: String(localized: "Mail & Messages", comment: "Storage kind: Mail and Messages data")
        case .appData: String(localized: "App Data & Caches", comment: "Storage kind: app data in the Library")
        case .trash: String(localized: "Trash", comment: "Storage kind: the macOS Trash")
        case .other: String(localized: "Other Files", comment: "Storage kind: files of any other type")
        }
    }

    var systemImage: String {
        switch self {
        case .apps: "square.grid.2x2"
        case .developer: "hammer"
        case .photos: "photo"
        case .videos: "film"
        case .music: "music.note"
        case .documents: "doc.text"
        case .archives: "archivebox"
        case .deviceBackups: "ipad.and.iphone"
        case .mail: "envelope"
        case .appData: "square.stack.3d.up"
        case .trash: "trash"
        case .other: "doc"
        }
    }

    var color: Color {
        switch self {
        case .apps: Color(hex: 0xFF6A13)
        case .developer: Color(hex: 0xC2410C)
        case .photos: Color(hex: 0xF5A524)
        case .videos: Color(hex: 0xE5484D)
        case .music: Color(hex: 0xD6409F)
        case .documents: Color(hex: 0x3E63DD)
        case .archives: Color(hex: 0x8E4EC6)
        case .deviceBackups: Color(hex: 0x12A594)
        case .mail: Color(hex: 0x0090FF)
        case .appData: Color(hex: 0x7C6F64)
        case .trash: Color(hex: 0xA8A29E)
        case .other: Color(hex: 0xE8C9A9)
        }
    }
}

struct StorageReport: Sendable {
    struct FileUsage: Identifiable, Sendable {
        var id: String { path }
        let path: String
        let bytes: Int64
    }

    struct FolderUsage: Identifiable, Sendable {
        var id: String { path }
        let path: String
        var bytes: Int64
        /// Largest files of this kind in the folder, at most `StorageAnalyzer.filesPerFolder`.
        var files: [FileUsage]
        /// All files of this kind in the folder, listed or not.
        var fileCount = 0
        /// Folders inside holding at least `StorageAnalyzer.minimumListedFile` of this kind, by path. Kept for
        /// personal kinds (`StorageAnalyzer.subfolderKinds`) so the person can see where e.g. photos pile up.
        var subfolders: [String: SubfolderUsage] = [:]

        /// Folders directly inside `path` (this folder or one of its subfolders), largest first.
        func children(of path: String) -> [(path: String, usage: SubfolderUsage)] {
            subfolders.filter { ($0.key as NSString).deletingLastPathComponent == path }
                .map { ($0.key, $0.value) }
                .sorted { $0.usage.bytes > $1.usage.bytes }
        }

        /// Skips folders that only pass everything on to one subfolder (`a/b/c` instead of three steps).
        func collapsed(_ path: String) -> String {
            var target = path
            while let usage = subfolders[target] {
                let kids = children(of: target)
                guard kids.count == 1, kids[0].usage.bytes == usage.bytes else { break }
                target = kids[0].path
            }
            return target
        }
    }

    struct SubfolderUsage: Sendable {
        var bytes: Int64 = 0
        var fileCount = 0
    }

    var date = Date()
    var totals: [StorageBucket: Int64] = [:]
    /// Per kind, the folders holding it, largest first.
    var folders: [StorageBucket: [FolderUsage]] = [:]
    var diskUsed: Int64 = 0
    var notes: [String] = []
    /// False when the report was made without Full Disk Access; Storage then offers to open the setting.
    var measuredWithFullDiskAccess = true

    var measured: Int64 { totals.values.reduce(0, +) }
    /// Used on the disk but outside what 1Cleaner reads: macOS, system data, other users, snapshots.
    var notMeasured: Int64 { max(0, diskUsed - measured) }

    var sortedBuckets: [(bucket: StorageBucket, bytes: Int64)] {
        StorageBucket.allCases.compactMap { bucket in
            guard let bytes = totals[bucket], bytes > 0 else { return nil }
            return (bucket, bytes)
        }.sorted { $0.bytes > $1.bytes }
    }
}

/// Walks the home folder and /Applications once (in parallel by top-level folder) and sorts every file into a
/// `StorageBucket`: by location first (an app bundle, a Photos library, ~/Library/Developer, node_modules, ...),
/// otherwise by file extension. Read-only. Hard-linked files count once; APFS clones can't be told apart.
enum StorageAnalyzer {
    static let filesPerFolder = 30
    /// Smaller files still count in totals but aren't listed one by one.
    static let minimumListedFile: Int64 = 1_000_000
    /// Kinds whose folders are broken down into subfolders; developer and app data have too many folders.
    static let subfolderKinds: Set<StorageBucket> = [.photos, .videos, .music, .documents, .archives]

    static func analyze(home: String, fullDiskAccess: Bool, progress: ScanProgress) async -> StorageReport {
        var roots: [(path: String, bucket: StorageBucket?)] = [("/Applications", .apps)]
        for name in FileInfo.children(home) where name != "Library" {
            roots.append((home + "/" + name, nil))
        }
        let library = home + "/Library"
        for name in FileInfo.children(library) {
            if !fullDiskAccess, ["Containers", "Group Containers", "Mail", "Messages", "Safari"].contains(name) { continue }
            roots.append((library + "/" + name, nil))
        }
        let walker = Walker(home: home, progress: progress)
        let parts: [Partial] = await Concurrency.map(roots, limit: 6) { root in
            walker.walk(root.path, forced: root.bucket)
        }

        var report = StorageReport()
        var folders: [StorageBucket: [String: StorageReport.FolderUsage]] = [:]
        var seenLinks = Set<Walker.FileKey>()
        for part in parts {
            for (bucket, bytes) in part.totals { report.totals[bucket, default: 0] += bytes }
            for (bucket, byFolder) in part.folders {
                for (path, usage) in byFolder {
                    var merged = folders[bucket]?[path] ?? StorageReport.FolderUsage(path: path, bytes: 0, files: [])
                    merged.bytes += usage.bytes
                    merged.fileCount += usage.fileCount
                    merged.subfolders.merge(usage.subfolders) {
                        StorageReport.SubfolderUsage(bytes: $0.bytes + $1.bytes, fileCount: $0.fileCount + $1.fileCount)
                    }
                    merged.files = Array((merged.files + usage.files).sorted { $0.bytes > $1.bytes }.prefix(filesPerFolder))
                    folders[bucket, default: [:]][path] = merged
                }
            }
            // A hard link seen from two roots: subtract the second copy.
            for (key, link) in part.links where !seenLinks.insert(key).inserted {
                report.totals[link.bucket, default: 0] -= link.bytes
            }
        }
        report.folders = folders.mapValues { Array($0.values.sorted { $0.bytes > $1.bytes }.prefix(200)) }
        if let disk = DiskSpace.current() { report.diskUsed = disk.used }
        if !fullDiskAccess {
            report.measuredWithFullDiskAccess = false
            report.notes.append(String(localized: """
                Without Full Disk Access, app containers, Mail, Messages and Safari data aren't measured and fall \
                under macOS and system data.
                """, comment: "Note on the Storage screen. Full Disk Access is the macOS privacy setting's name."))
        }
        report.date = Date()
        return report
    }

    struct Partial: Sendable {
        var totals: [StorageBucket: Int64] = [:]
        var folders: [StorageBucket: [String: StorageReport.FolderUsage]] = [:]
        /// Hard-linked files of this root, to count them once across roots.
        var links: [Walker.FileKey: (bucket: StorageBucket, bytes: Int64)] = [:]
    }

    struct Walker: Sendable {
        struct FileKey: Hashable, Sendable {
            let device: Int32
            let inode: UInt64
        }

        struct SubfolderKey: Hashable {
            let bucket: StorageBucket
            let group: String
            let path: String
        }

        let home: String
        let progress: ScanProgress

        static let devFolderNames: Set<String> = [
            "node_modules", ".next", ".build", "Pods", ".gradle", ".dart_tool", ".venv", "DerivedData", ".turbo",
        ]
        static let devHomeFolders: Set<String> = [
            ".gradle", ".android", ".npm", ".cache", ".cargo", ".rustup", ".m2", ".bun", ".nvm", ".pyenv", ".docker",
            ".ollama", ".lmstudio", ".yarn", ".pnpm-store", ".deno", ".swiftpm", ".cocoapods", ".pub-cache", ".conda",
            ".rbenv", ".gem", ".volta", ".colima", ".orbstack", ".lima",
        ]
        static let photoExtensions: Set<String> = [
            "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp", "raw", "dng", "cr2", "cr3",
            "nef", "arw", "orf", "rw2", "psd", "svg", "avif",
        ]
        static let videoExtensions: Set<String> = [
            "mov", "mp4", "m4v", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg", "3gp", "mts", "m2ts", "prores",
        ]
        static let audioExtensions: Set<String> = [
            "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus", "alac", "caf", "m4b", "wma",
        ]
        static let documentExtensions: Set<String> = [
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf", "md", "csv",
            "odt", "ods", "odp", "epub", "mobi", "djvu", "fb2",
        ]
        static let archiveExtensions: Set<String> = [
            "zip", "dmg", "pkg", "mpkg", "iso", "xip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst",
            "sparseimage", "sparsebundle", "img",
        ]

        /// The bucket a folder's whole content belongs to, decided by where it is.
        func forcedBucket(path: String, name: String, parent: String) -> StorageBucket? {
            let lower = name.lowercased()
            if lower.hasSuffix(".app") { return .apps }
            if lower.hasSuffix(".photoslibrary") || lower.hasSuffix(".photolibrary") { return .photos }
            if lower.hasSuffix(".musiclibrary") || lower.hasSuffix(".tvlibrary") { return .music }
            if lower.hasSuffix(".imovielibrary") || lower.hasSuffix(".fcpbundle") { return .videos }
            if lower.hasSuffix(".sparsebundle") { return .archives }
            if Self.devFolderNames.contains(name) { return .developer }
            if parent == home {
                if name == ".Trash" { return .trash }
                if Self.devHomeFolders.contains(name) { return .developer }
            }
            let library = home + "/Library"
            if parent == library {
                switch name {
                case "Developer", "Android": return .developer
                case "Mail", "Messages": return .mail
                case "Caches", "Application Support", "Containers", "Group Containers", "Logs", "Preferences",
                     "Saved Application State", "WebKit", "HTTPStorages", "Cookies":
                    return .appData
                default: return nil
                }
            }
            if path == library + "/Application Support/MobileSync" { return .deviceBackups }
            if path == library + "/Containers/com.docker.docker" { return .developer }
            if path == library + "/Containers/com.apple.mail" { return .mail }
            return nil
        }

        func bucket(forFileNamed name: String) -> StorageBucket {
            let ext = (name as NSString).pathExtension.lowercased()
            if Self.photoExtensions.contains(ext) { return .photos }
            if Self.videoExtensions.contains(ext) { return .videos }
            if Self.audioExtensions.contains(ext) { return .music }
            if Self.documentExtensions.contains(ext) { return .documents }
            if Self.archiveExtensions.contains(ext) { return .archives }
            return .other
        }

        /// The folder a file is listed under: the folder that decided its bucket, or its folder up to three
        /// levels below home (`~/Developer/projects/app`).
        func groupFolder(for directory: String) -> String {
            guard directory.hasPrefix(home + "/") else { return directory }
            let parts = directory.dropFirst(home.count + 1).split(separator: "/").prefix(3)
            return home + "/" + parts.joined(separator: "/")
        }

        func walk(_ root: String, forced rootBucket: StorageBucket?) -> Partial {
            var part = Partial()
            // Per fts level: the bucket forced on this folder's content and the folder files are listed under.
            var forcedStack: [StorageBucket?] = []
            var groupStack: [String] = []
            // Per fts level: the folder's path, for subfolder totals (kept outside `part` so updates stay in place).
            var pathStack: [String] = []
            var subfolderTotals: [SubfolderKey: StorageReport.SubfolderUsage] = [:]
            var visited = 0
            // Smallest listed size per kind and folder, so path strings are built only for files that can enter a
            // top list. Per kind: big files of one kind must not keep another kind's files out of its list.
            var listThreshold: [String: Int64] = [:]
            var seenLinks = Set<FileKey>()

            guard let rootCopy = strdup(root) else { return part }
            defer { free(rootCopy) }
            var paths: [UnsafeMutablePointer<CChar>?] = [rootCopy, nil]
            guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return part }
            defer { fts_close(fts) }

            while let entry = fts_read(fts) {
                visited += 1
                if visited % 4096 == 0 {
                    progress.add(entries: 4096)
                    if Task.isCancelled { break }
                }
                let level = Int(entry.pointee.fts_level)
                switch Int32(entry.pointee.fts_info) {
                case FTS_D:
                    forcedStack.removeLast(max(0, forcedStack.count - level))
                    groupStack.removeLast(max(0, groupStack.count - level))
                    pathStack.removeLast(max(0, pathStack.count - level))
                    let path = entry.path
                    pathStack.append(path)
                    let inherited = forcedStack.last ?? nil
                    var forced = inherited
                    var group = groupStack.last ?? groupFolder(for: path)
                    if level == 0, let rootBucket {
                        forced = rootBucket
                    }
                    if inherited == nil {
                        let parent = (path as NSString).deletingLastPathComponent
                        if let bucket = forcedBucket(path: path, name: entry.name, parent: parent) {
                            forced = bucket
                            group = path
                        } else {
                            group = groupFolder(for: path)
                        }
                    }
                    // Each app bundle is its own folder in the list, wherever it sits under /Applications.
                    if forced == .apps, entry.name.hasSuffix(".app"), !group.hasSuffix(".app") { group = path }
                    forcedStack.append(forced)
                    groupStack.append(group)
                case FTS_F:
                    // The parent folder is at level - 1: drop entries of sibling folders walked before this file.
                    forcedStack.removeLast(max(0, forcedStack.count - level))
                    groupStack.removeLast(max(0, groupStack.count - level))
                    pathStack.removeLast(max(0, pathStack.count - level))
                    guard let stat = entry.pointee.fts_statp?.pointee else { continue }
                    if stat.st_nlink > 1, !seenLinks.insert(FileKey(device: stat.st_dev, inode: stat.st_ino)).inserted {
                        continue
                    }
                    let bytes = Int64(stat.st_blocks) * 512
                    let forced = forcedStack.last ?? nil
                    let bucket = forced ?? (rootBucket ?? bucket(forFileNamed: entry.name))
                    // Unclassified files inside ~/Library are app data, not the person's files.
                    let finalBucket = (bucket == .other && root.hasPrefix(home + "/Library")) ? .appData : bucket
                    let group = groupStack.last ?? root
                    part.totals[finalBucket, default: 0] += bytes
                    var usage = part.folders[finalBucket]?[group] ?? StorageReport.FolderUsage(path: group, bytes: 0, files: [])
                    usage.bytes += bytes
                    usage.fileCount += 1
                    if StorageAnalyzer.subfolderKinds.contains(finalBucket) {
                        // Every folder between the listed folder and the file gets the file's size.
                        for folder in pathStack.reversed() {
                            guard folder.count > group.count, folder.hasPrefix(group + "/") else { break }
                            let key = SubfolderKey(bucket: finalBucket, group: group, path: folder)
                            subfolderTotals[key, default: StorageReport.SubfolderUsage()].bytes += bytes
                            subfolderTotals[key, default: StorageReport.SubfolderUsage()].fileCount += 1
                        }
                    }
                    let thresholdKey = finalBucket.rawValue + "|" + group
                    if bytes >= StorageAnalyzer.minimumListedFile, bytes > listThreshold[thresholdKey, default: 0] {
                        usage.files.append(StorageReport.FileUsage(path: entry.path, bytes: bytes))
                        if usage.files.count > StorageAnalyzer.filesPerFolder * 2 {
                            usage.files = Array(usage.files.sorted { $0.bytes > $1.bytes }.prefix(StorageAnalyzer.filesPerFolder))
                            listThreshold[thresholdKey] = usage.files.last?.bytes ?? 0
                        }
                    }
                    part.folders[finalBucket, default: [:]][group] = usage
                    if stat.st_nlink > 1 {
                        part.links[FileKey(device: stat.st_dev, inode: stat.st_ino)] = (finalBucket, bytes)
                    }
                default:
                    continue
                }
            }
            progress.add(entries: visited % 4096)
            for (key, usage) in subfolderTotals where usage.bytes >= StorageAnalyzer.minimumListedFile {
                part.folders[key.bucket]?[key.group]?.subfolders[key.path] = usage
            }
            for (bucket, byFolder) in part.folders {
                part.folders[bucket] = byFolder.mapValues { usage in
                    var trimmed = usage
                    trimmed.files = Array(usage.files.sorted { $0.bytes > $1.bytes }.prefix(StorageAnalyzer.filesPerFolder))
                    return trimmed
                }
            }
            return part
        }
    }
}
