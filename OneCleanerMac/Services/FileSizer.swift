import Darwin
import Foundation

/// Allocated size of a file or folder tree, measured with `fts`: never follows symbolic links, stays on one
/// volume, counts a hard-linked file once per measurement and stops promptly when the task is cancelled.
enum FileSizer {
    struct Measurement: Sendable {
        var bytes: Int64 = 0
        /// Sum of file lengths: the same on any file system, unlike allocated `bytes`. Used to verify copies.
        var logicalBytes: Int64 = 0
        var files = 0
        /// Folders or files that could not be read (permissions, Full Disk Access).
        var unreadable = 0
        /// False when the root itself could not be read.
        var rootReadable = true
        /// Newest modification time of anything inside (seconds since 1970), for "nothing changed for N days".
        var latestChange: Int = 0

        var latestChangeDate: Date { Date(timeIntervalSince1970: TimeInterval(latestChange)) }
    }

    static func measure(_ path: String, progress: ScanProgress? = nil) -> Measurement {
        var result = Measurement()
        var seenLinks = Set<FileKey>()
        var visited = 0
        var stopped = false

        let whole = walk(path) { entry in
            visited += 1
            if visited % 4096 == 0 {
                progress?.add(entries: 4096)
                if Task.isCancelled {
                    stopped = true
                    return .stop
                }
            }
            switch Int32(entry.pointee.fts_info) {
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let stat = entry.pointee.fts_statp?.pointee else { break }
                if stat.st_nlink > 1, !seenLinks.insert(FileKey(device: stat.st_dev, inode: stat.st_ino)).inserted {
                    break
                }
                result.bytes += Int64(stat.st_blocks) * 512
                if Int32(entry.pointee.fts_info) == FTS_F { result.logicalBytes += Int64(stat.st_size) }
                result.files += 1
                result.latestChange = max(result.latestChange, Int(stat.st_mtimespec.tv_sec), Int(stat.st_ctimespec.tv_sec))
            case FTS_D:
                guard let stat = entry.pointee.fts_statp?.pointee else { break }
                result.bytes += Int64(stat.st_blocks) * 512
                result.latestChange = max(result.latestChange, Int(stat.st_mtimespec.tv_sec))
            case FTS_DNR, FTS_ERR, FTS_NS:
                if entry.pointee.fts_level == 0 { result.rootReadable = false }
                result.unreadable += 1
            default:
                break
            }
            return .continue
        }
        progress?.add(entries: visited % 4096)
        // A walk stopped part way measured only part of it: it's not offered with that size.
        if stopped {
            result.unreadable += 1
            result.rootReadable = false
        } else if !whole {
            result.unreadable += 1
            if visited == 0 { result.rootReadable = false }
        }
        return result
    }

    enum WalkAction { case `continue`, skip, stop }

    /// Pre-order walk of `root` with `stat` information. `visit` may skip a directory's contents or stop.
    /// False when the walk couldn't start or broke off with an error (not when `visit` stopped it): then whatever
    /// it saw isn't the whole tree.
    @discardableResult
    static func walk(_ root: String, visit: (UnsafeMutablePointer<FTSENT>) -> WalkAction) -> Bool {
        guard let rootCopy = strdup(root) else { return false }
        defer { free(rootCopy) }
        var paths: [UnsafeMutablePointer<CChar>?] = [rootCopy, nil]
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return false }
        defer { fts_close(fts) }
        while true {
            // fts_read ends with nil both at the end (errno 0) and on an error.
            errno = 0
            guard let entry = fts_read(fts) else { return errno == 0 }
            if Int32(entry.pointee.fts_info) == FTS_DP { continue }
            switch visit(entry) {
            case .continue: break
            case .skip: fts_set(fts, entry, FTS_SKIP)
            case .stop: return true
            }
        }
    }

    private struct FileKey: Hashable {
        let device: Int32
        let inode: UInt64
    }
}

extension UnsafeMutablePointer where Pointee == FTSENT {
    var path: String { String(cString: pointee.fts_path) }

    /// The entry's own name without building the full path string.
    var name: String {
        withUnsafePointer(to: &pointee.fts_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(pointee.fts_namelen) + 1) { String(cString: $0) }
        }
    }
}

enum FileInfo {
    static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    static func isDirectory(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    static func isSymbolicLink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }

    static func modificationDate(_ path: String) -> Date? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
    }

    /// Visible and hidden names in a directory; empty when it can't be read.
    static func children(_ path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    }
}
