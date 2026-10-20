import Darwin
import Foundation

/// "Move to Another Disk": copies an item with `ditto` into a new folder of its own on the other disk, verifies
/// the copy (same files, same total length) and that the original didn't change meanwhile, puts the copy under its
/// name without replacing anything, and only then moves the original to the Trash. A failed or stopped move leaves
/// the original untouched and removes only that folder, never anything that was already there.
enum Mover {
    enum Outcome: Sendable {
        case moved(destination: String)
        case failed(String)
    }

    /// Files and their total length, ignoring what file systems add on their own (`.DS_Store`, AppleDouble `._*`
    /// files on exFAT/FAT drives), so a copy compares equal to its source.
    struct Fingerprint: Hashable, Sendable {
        var files = 0
        var bytes: Int64 = 0
        /// Folders or files that couldn't be read; a source with any isn't copied.
        var unreadable = 0
        /// Newest modification time of the files (nanoseconds): the original must still have it after copying.
        var latestChange: Int64 = 0
        /// Every file's path inside the item and its length, summed as hashes so the walk order doesn't matter: a
        /// copy must have the same files, not just as many bytes.
        var layout = 0
        /// The same with each file's modification time and inode: the original must be unchanged, file by file.
        var stamps = 0
        /// The same with each file's status-change time, which no tool can set back. Compared only by `identical`:
        /// opening a file changes it (macOS updates its attributes), so "unchanged since the scan" (`==`) leaves it out.
        var statusStamps = 0

        static func == (lhs: Fingerprint, rhs: Fingerprint) -> Bool {
            lhs.files == rhs.files && lhs.bytes == rhs.bytes && lhs.unreadable == rhs.unreadable
                && lhs.latestChange == rhs.latestChange && lhs.layout == rhs.layout && lhs.stamps == rhs.stamps
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(layout)
            hasher.combine(stamps)
        }

        /// Exactly these files, status-change times too: a copy just placed, which nobody has opened.
        func identical(_ other: Fingerprint) -> Bool { self == other && statusStamps == other.statusStamps }

        /// A copy keeps the files, their names and lengths; its folders get their own dates.
        func matchesCopy(_ copy: Fingerprint) -> Bool {
            files == copy.files && bytes == copy.bytes && unreadable == copy.unreadable && layout == copy.layout
        }
    }

    /// `stoppable`: Stop cuts the walk short. A rollback walks to the end, so a copy is never mistaken for changed.
    static func fingerprint(_ path: String, stoppable: Bool = true) -> Fingerprint {
        var result = Fingerprint()
        var visited = 0
        let whole = FileSizer.walk(path) { entry in
            visited += 1
            // A walk cut short counts as unreadable: it never matches, so nothing is removed on its word.
            if stoppable, Task.isCancelled {
                result.unreadable += 1
                return .stop
            }
            let info = Int32(entry.pointee.fts_info)
            if info == FTS_DNR || info == FTS_ERR || info == FTS_NS {
                result.unreadable += 1
                return .continue
            }
            // Folders count by name too: one made inside after the scan, even empty, is a change.
            if info == FTS_D, entry.pointee.fts_level > 0 {
                var folder = Hasher()
                folder.combine(entry.path.dropFirst(path.count))
                folder.combine("/")
                result.layout &+= folder.finalize()
                return .continue
            }
            guard info == FTS_F || info == FTS_SL, let stat = entry.pointee.fts_statp?.pointee else {
                return .continue
            }
            let name = entry.name
            if name == ".DS_Store" || name.hasPrefix("._") { return .continue }
            result.files += 1
            result.bytes += Int64(stat.st_size)
            let modified = Int64(stat.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(stat.st_mtimespec.tv_nsec)
            result.latestChange = max(result.latestChange, modified)
            let relative = entry.path.dropFirst(path.count)
            var file = Hasher()
            file.combine(relative)
            file.combine(stat.st_size)
            result.layout &+= file.finalize()
            file = Hasher()
            file.combine(relative)
            file.combine(stat.st_size)
            file.combine(modified)
            // The same file, not one put in its place with the same name, length and date.
            file.combine(stat.st_ino)
            result.stamps &+= file.finalize()
            file = Hasher()
            file.combine(relative)
            file.combine(stat.st_ctimespec.tv_sec)
            file.combine(stat.st_ctimespec.tv_nsec)
            result.statusStamps &+= file.finalize()
            return .continue
        }
        // Nothing read at all (the path couldn't be opened), or a walk broken off, proves nothing.
        if visited == 0 || !whole { result.unreadable += 1 }
        return result
    }

    /// Why `folder` can't receive the item, or nil.
    static func problem(destination folder: String, for targets: [FileTarget]) -> String? {
        var folderInfo = stat()
        guard lstat(folder, &folderInfo) == 0, (folderInfo.st_mode & S_IFMT) == S_IFDIR else {
            return String(localized: "The destination folder isn't available.", comment: "Move to Another Disk error")
        }
        guard access(folder, W_OK) == 0 else {
            return String(localized: "1Cleaner can't write to that folder.", comment: "Move to Another Disk error")
        }
        if targets.contains(where: { $0.device == folderInfo.st_dev }) {
            return String(localized: """
                That folder is on the same disk, so moving there frees no space. Choose another disk.
                """, comment: "Move to Another Disk error")
        }
        // Every part lands in the folder under its own name: two parts named alike (an app's `Caches/<id>` and
        // `Application Support/<id>`) would merge into one copy.
        var names = Set<String>()
        for target in targets {
            let name = (target.path as NSString).lastPathComponent
            if !names.insert(name.lowercased()).inserted {
                return String(localized: "Two parts of it are named “\(name)”, so they can't go into one folder.",
                              comment: "Move to Another Disk error. The placeholder is a file or folder name.")
            }
            // `._<name>` too: on exFAT that file belongs to the item of that name.
            if FileInfo.exists(folder + "/" + name) || FileInfo.exists(folder + "/._" + name) {
                return String(localized: "“\(name)” already exists in that folder.",
                              comment: "Move to Another Disk error. The placeholder is a file or folder name.")
            }
        }
        return nil
    }

    /// Bytes still free on the destination volume, for progress and the space check.
    static func freeBytes(_ folder: String) -> Int64? {
        let values = try? URL(fileURLWithPath: folder).resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    static func move(
        _ item: CleanupItem, to folder: String, progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async -> Outcome {
        guard case .trash(let targets) = item.removal, !targets.isEmpty else {
            return .failed(String(localized: "Only files and folders can be moved to another disk.",
                                  comment: "Move to Another Disk error"))
        }
        for target in targets {
            if let problem = Remover.problem(with: target) { return .failed(problem) }
            // A running app, emulator or editor changes its files while they're copied.
            if let problem = await Remover.runningProblem(target.path) ?? Remover.usedByRunningApp(target) {
                return .failed(problem)
            }
        }
        if let problem = problem(destination: folder, for: targets) { return .failed(problem) }

        let sources = targets.map { ($0, fingerprint($0.path)) }
        // A copy can only be checked against what could be read; nothing is copied when part of it can't be.
        if sources.contains(where: { $0.1.unreadable > 0 }) {
            return .failed(String(localized: "Some files in it can't be read, so the copy couldn't be checked. Nothing was changed.",
                                  comment: "Move to Another Disk error"))
        }
        // On exFAT and FAT a file is written once more under its final name (see `placeWithoutReplacing`).
        let fileBytes = sources.filter { !FileInfo.isDirectory($0.0.path) }.reduce(0) { $0 + $1.1.bytes }
        let total = sources.reduce(0) { $0 + $1.1.bytes } + (lacksExclusiveRename(folder) ? fileBytes : 0)
        if let free = freeBytes(folder), free < total + total / 50 + 50_000_000 {
            return .failed(String(localized: """
                Not enough space on that disk: \(total.formattedBytes) needed, \(free.formattedBytes) free.
                """, comment: "Move to Another Disk error. Placeholders: sizes such as \"12 GB\"."))
        }

        // Everything is copied into a folder only this move created; it is the only thing a failure removes.
        // Visible, so a copy cut short (a disk pulled out) is easy to find and delete.
        let work = folder + "/1Cleaner unfinished move " + UUID().uuidString.prefix(8)
        guard mkdir(work, 0o700) == 0 else {
            return .failed(String(localized: "1Cleaner can't write to that folder.", comment: "Move to Another Disk error"))
        }
        let startFree = freeBytes(folder) ?? 0
        let progressTask = Task.detached {
            while !Task.isCancelled {
                if let free = freeBytes(folder) { progress(min(total, max(0, startFree - free)), total) }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        defer { progressTask.cancel() }

        var copyPrints: [Fingerprint] = []
        for (target, sourcePrint) in sources {
            let copyPath = work + "/" + (target.path as NSString).lastPathComponent
            let copy: ProcessRunner.Output
            do {
                // `ditto` keeps metadata, extended attributes, permissions and hard links.
                copy = try await ProcessRunner.run("/usr/bin/ditto", [target.path, copyPath], timeout: .seconds(6 * 3600))
            } catch {
                removeWork(work)
                return .failed(Task.isCancelled ? stoppedMessage : error.localizedDescription)
            }
            guard copy.succeeded, !Task.isCancelled else {
                removeWork(work)
                return .failed(Task.isCancelled
                    ? stoppedMessage
                    : String(localized: "Copy failed: \(copy.errorMessage)",
                             comment: "Move to Another Disk error. The placeholder is the copy tool's message."))
            }
            let copyPrint = fingerprint(copyPath)
            guard !Task.isCancelled else {
                removeWork(work)
                return .failed(stoppedMessage)
            }
            copyPrints.append(copyPrint)
            guard sourcePrint.matchesCopy(copyPrint) else {
                removeWork(work)
                return .failed(String(localized: """
                    The copy didn't match the original (\(copyPrint.files) of \(sourcePrint.files) files). \
                    The original wasn't changed.
                    """, comment: "Move to Another Disk error. Placeholders: files copied; files in the original."))
            }
            // A file changed in the original during the copy: the copy holds the older version.
            guard fingerprint(target.path) == sourcePrint else {
                removeWork(work)
                return .failed(Task.isCancelled ? stoppedMessage : changedMessage)
            }
        }

        guard !Task.isCancelled else {
            removeWork(work)
            return .failed(stoppedMessage)
        }
        // Every part once more, now that all are copied: an earlier part may have changed while later ones copied.
        for (target, sourcePrint) in sources where fingerprint(target.path) != sourcePrint {
            removeWork(work)
            return .failed(Task.isCancelled ? stoppedMessage : changedMessage)
        }

        // Each copy takes its final name only where nothing has that name yet.
        var placed: [(copy: String, final: String, device: Int32, inode: UInt64, print: Fingerprint)] = []
        // Parts placed already go back only while they're still the copies placed here, file by file as they were
        // placed: a copy someone saved into after it took its name stays where it is (with the original also kept).
        func rollBack() {
            for item in placed.reversed() {
                var now = stat()
                if lstat(item.final, &now) == 0, now.st_dev == item.device, now.st_ino == item.inode,
                   item.print.unreadable == 0, fingerprint(item.final, stoppable: false).identical(item.print),
                   lstat(item.final, &now) == 0, now.st_dev == item.device, now.st_ino == item.inode {
                    _ = rename(item.final, item.copy)
                }
            }
            removeWork(work)
        }
        for ((target, _), copyPrint) in zip(sources, copyPrints) {
            let name = (target.path as NSString).lastPathComponent
            let final = folder + "/" + name
            switch placeWithoutReplacing(work + "/" + name, at: final) {
            case .placed(let device, let inode):
                // A folder took its name by rename, which leaves its files as the copy check saw them; a file on
                // exFAT was written again, so its state right after that is what a rollback compares.
                let print = FileInfo.isDirectory(final) ? copyPrint : fingerprint(final, stoppable: false)
                placed.append((work + "/" + name, final, device, inode, print))
            case .taken:
                rollBack()
                return .failed(String(localized: "“\(name)” already exists in that folder.",
                                      comment: "Move to Another Disk error. The placeholder is a file or folder name."))
            case .failed(let message):
                rollBack()
                return .failed(Task.isCancelled
                    ? stoppedMessage
                    : String(localized: "Copy failed: \(message)",
                             comment: "Move to Another Disk error. The placeholder is the copy tool's message."))
            }
        }
        // Stopped during the last copies (exFAT writes files once more): the original stays, the copies go.
        guard !Task.isCancelled else {
            rollBack()
            return .failed(stoppedMessage)
        }
        // On exFAT the last copies take as long as the first: the originals are checked once more after them.
        for (target, sourcePrint) in sources where fingerprint(target.path) != sourcePrint {
            rollBack()
            return .failed(Task.isCancelled ? stoppedMessage : changedMessage)
        }
        removeWork(work)
        progress(total, total)

        let destination = placed[0].final
        switch await Remover.moveToTrash(targets) {
        case .movedToTrash, .removed:
            return .moved(destination: destination)
        case .failed(let reason):
            return .failed(String(localized: """
                Copied and verified, but the original couldn't go to the Trash: \(reason)
                """, comment: "Move to Another Disk error. The placeholder is the reason."))
        }
    }

    private enum Placement {
        case placed(device: Int32, inode: UInt64)
        /// Something already has that name.
        case taken
        case failed(String)
    }

    /// Puts `source` at `destination` only when nothing is there, never replacing anything, and returns what is at
    /// `destination` now. Disks without an exclusive rename (exFAT): a folder claims the name with an empty folder
    /// only this move creates (a rename onto a folder that isn't empty fails, so nothing of anyone else's can be
    /// replaced); a file is written into a file this move creates exclusively, and its name must still lead there.
    private static func placeWithoutReplacing(_ source: String, at destination: String) -> Placement {
        func placed() -> Placement {
            var info = stat()
            return lstat(destination, &info) == 0 ? .placed(device: info.st_dev, inode: info.st_ino) : .taken
        }
        func failure(_ code: Int32) -> Placement {
            code == EEXIST || code == ENOTEMPTY ? .taken : .failed(String(cString: strerror(code)))
        }
        if renamex_np(source, destination, UInt32(RENAME_EXCL)) == 0 { return placed() }
        guard errno == ENOTSUP || errno == EINVAL else { return failure(errno) }
        var info = stat()
        guard lstat(source, &info) == 0 else { return failure(errno) }
        if (info.st_mode & S_IFMT) == S_IFDIR {
            guard mkdir(destination, 0o700) == 0 else { return failure(errno) }
            if rename(source, destination) == 0 { return placed() }
            let code = errno
            _ = rmdir(destination)  // only an empty folder can go
            return failure(code)
        }
        let output = open(destination, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard output >= 0 else { return failure(errno) }
        var created = stat()
        guard fstat(output, &created) == 0 else {
            let code = errno
            close(output)
            return failure(code)
        }
        let input = open(source, O_RDONLY)
        var written = stat()
        // Stop stops the copy too: copyfile asks between chunks whether to go on. Any error quits: a failed write
        // would otherwise be written again (forever on a full disk), and a lost attribute or resource fork would
        // leave a copy that isn't whole while the original goes to the Trash.
        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }
        let goOn: copyfile_callback_t = { _, stage, _, _, _, _ in
            stage == COPYFILE_ERR || Task.isCancelled ? COPYFILE_QUIT : COPYFILE_CONTINUE
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(goOn, to: UnsafeRawPointer.self))
        let copied = input >= 0 && fcopyfile(input, output, state, copyfile_flags_t(COPYFILE_ALL)) == 0
            && fstat(output, &written) == 0 && written.st_size == info.st_size
        let code = errno
        if input >= 0 { close(input) }
        close(output)
        var now = stat()
        let mine = lstat(destination, &now) == 0 && now.st_dev == created.st_dev && now.st_ino == created.st_ino
        if copied, mine { return .placed(device: created.st_dev, inode: created.st_ino) }
        if mine { _ = unlink(destination) }
        return mine ? .failed(String(cString: strerror(code == 0 ? EIO : code))) : .taken
    }

    /// exFAT and FAT disks: no exclusive rename, so files are written once more under their final names.
    private static func lacksExclusiveRename(_ folder: String) -> Bool {
        var info = statfs()
        guard statfs(folder, &info) == 0 else { return false }
        let type = withUnsafeBytes(of: info.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return ["exfat", "msdos"].contains(type)
    }

    private static var changedMessage: String {
        String(localized: "The original changed while it was copied. Nothing was changed; try again.",
               comment: "Move to Another Disk error")
    }

    private static var stoppedMessage: String {
        String(localized: "Stopped. The original wasn't changed.",
               comment: "Move to Another Disk: the person stopped the copy")
    }

    /// Removes the folder this move created, with whatever is still in it; nothing outside it.
    private static func removeWork(_ work: String) {
        try? FileManager.default.removeItem(atPath: work)
    }
}
