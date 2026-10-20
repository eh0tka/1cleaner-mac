import CryptoKit
import Darwin
import Foundation

/// Exact copies among the files the project walk saw. Same size first, then the first 64 KB,
/// then the whole content (SHA-256). Every copy is listed, grouped by set; the person picks which to remove and
/// one copy of each set always stays (`AppModel.setSelected`).
///
/// Never listed: hard links (one file under two names) and APFS clones (Finder's Duplicate shares the disk space,
/// so removing a clone frees nothing). Files that live only in iCloud are skipped by the walk: reading them would
/// download them.
enum DuplicateFinder {
    static let minimumSize: Int64 = 1_000_000

    struct File: Sendable {
        let path: String
        /// Logical size: what makes two files candidates.
        let size: Int64
        /// Space on disk: what removing the copy frees.
        let allocated: Int64
        let device: Int32
        let inode: UInt64
        /// Length and modification time when the walk saw it; a copy changed since then isn't offered.
        let stamp: FileTarget.ContentStamp
    }

    static func items(_ files: [File], progress: ScanProgress) async -> [CleanupItem] {
        // Same size, one entry per file on disk (hard links share device and inode).
        var seen = Set<String>()
        let unique = files.filter { seen.insert("\($0.device):\($0.inode)").inserted }
        let sameSize = Dictionary(grouping: unique, by: \.size).values.filter { $0.count > 1 }
            .map { $0.filter { !sharesSpace($0.path) } }
            .filter { $0.count > 1 }
        guard !sameSize.isEmpty else { return [] }

        let sets: [[[File]]] = await Concurrency.map(sameSize, limit: 4) { group in
            var byHead: [String: [File]] = [:]
            for file in group {
                guard !Task.isCancelled, let head = digest(file, limit: 65_536) else { continue }
                byHead[head, default: []].append(file)
            }
            var result: [[File]] = []
            for candidates in byHead.values where candidates.count > 1 {
                // Files no bigger than the head are already compared whole.
                if candidates[0].size <= 65_536 {
                    result.append(candidates)
                    continue
                }
                var byContent: [String: [File]] = [:]
                for file in candidates {
                    guard !Task.isCancelled, let full = digest(file, limit: nil) else { continue }
                    byContent[full, default: []].append(file)
                }
                result += byContent.values.filter { $0.count > 1 }
            }
            progress.add(entries: group.count)
            return result
        }

        var items: [CleanupItem] = []
        for set in sets.flatMap({ $0 }) {
            let ordered = set.map { ($0, created($0.path)) }
                .sorted { ($0.1 ?? .distantFuture, $0.0.path) < ($1.1 ?? .distantFuture, $1.0.path) }
            // A copy edited while the set was compared is no longer a copy; a set left with one file isn't a set.
            let current = ordered.compactMap { file, date in
                FileTarget(path: file.path, expected: file.stamp, device: file.device, inode: file.inode).map { (file, date, $0) }
            }
            guard current.count > 1 else { continue }
            let group = current[0].0.path
            for (index, (file, date, target)) in current.enumerated() {
                var item = CleanupItem(
                    id: file.path,
                    category: .duplicates,
                    title: PathDisplay.abbreviated(file.path),
                    badge: index == 0 ? String(localized: "Oldest copy", comment: "Badge of the oldest copy among duplicates") : nil,
                    detail: date.map {
                        String(localized: "created \($0.relativeDescription)",
                               comment: "Fact in a Duplicates row's detail line; %@ is a relative date like '3 months ago'")
                    } ?? "",
                    size: file.allocated,
                    removal: .trash([target]),
                    date: date
                )
                item.duplicateGroup = group
                item.isOldestCopy = index == 0
                items.append(item)
            }
        }
        return items
    }

    /// APFS clones may share all or part of their blocks with another file.
    private static func sharesSpace(_ path: String) -> Bool {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.mayShareFileContentKey]))?.mayShareFileContent ?? false
    }

    private static func created(_ path: String) -> Date? {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    /// SHA-256 of the first `limit` bytes, or of the whole file when `limit` is nil; nil unless the file opened is
    /// still the regular file the walk saw (opened without waiting, so a pipe put in its place can't hang the scan).
    private static func digest(_ file: File, limit: Int?) -> String? {
        let descriptor = open(file.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_dev == file.device, info.st_ino == file.inode else { return nil }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            if Task.isCancelled { return nil }
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: min(1 << 20, remaining))
            } catch {
                return nil
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
