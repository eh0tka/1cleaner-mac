import AppKit
import Darwin
import Foundation

/// Xcode caches from `KnownLocations`, plus copies of Xcode in /Applications other than the selected one.
struct XcodeScanner: Scanner {
    var categories: [CategoryID] { [.xcode] }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        var output = await LocationScanner(category: .xcode, locations: KnownLocations.xcode).scan(context)[.xcode]
            ?? ScanOutput()
        output.items = Self.labelArchives(output.items)
        let selected = await Self.selectedXcode()
        // Compared after resolving links: `Xcode.app` is often a link to `Xcode-16.2.0.app` (xcodes, Xcodes.app).
        let selectedResolved = selected.flatMap(Self.resolved)
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path }.compactMap(Self.resolved))
        let copies = FileInfo.children("/Applications")
            .filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
            .map { "/Applications/" + $0 }
            .filter { !FileInfo.isSymbolicLink($0) && Self.resolved($0) != selectedResolved }
        let apps: [CleanupItem?] = await Concurrency.map(copies, limit: 2) { path -> CleanupItem? in
            let measurement = FileSizer.measure(path, progress: context.progress)
            guard measurement.rootReadable, let target = FileTarget(path: path) else { return nil }
            let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
            let version = info?["CFBundleShortVersionString"] as? String
            return CleanupItem(
                id: path,
                category: .xcode,
                title: (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
                    + (version.map { " \($0)" } ?? ""),
                badge: String(localized: "Xcode app", comment: "Badge of another copy of Xcode in /Applications"),
                detail: selected.map {
                    String(localized: "Another copy of Xcode; the one selected for builds is \(($0 as NSString).lastPathComponent)",
                           comment: "Detail of another Xcode copy; %@ is the selected Xcode's name like Xcode.app")
                } ?? String(localized: "Another copy of Xcode; the one selected for builds is not this one",
                            comment: "Detail of another Xcode copy when the selected Xcode is unknown"),
                size: measurement.bytes,
                removal: .trash([target]),
                lockedReason: Self.resolved(path).map(running.contains) == true
                    ? String(localized: "Running. Quit it to remove it.", comment: "Why a running app can't be selected") : nil,
                date: FileInfo.modificationDate(path)
            )
        }
        output.items = (output.items + apps.compactMap { $0 }).sorted { $0.size > $1.size }
        return [.xcode: output]
    }

    /// Archives grouped by app: the newest archive of each app stays Risky; older ones are
    /// Ask AI, since the build comes back from its git tag and only that build's crash symbols are lost.
    static func labelArchives(_ items: [CleanupItem]) -> [CleanupItem] {
        struct Archive {
            let index: Int
            let app: String
            let version: String?
            let build: String?
            let created: Date
            let uploaded: Bool
        }
        var archives: [Archive] = []
        for (index, item) in items.enumerated() {
            guard let path = item.revealPath, path.contains("/Xcode/Archives/"), path.hasSuffix(".xcarchive") else { continue }
            let info = NSDictionary(contentsOfFile: path + "/Info.plist")
            let properties = info?["ApplicationProperties"] as? [String: Any]
            let distributions = info?["Distributions"] as? [[String: Any]] ?? []
            let uploaded = distributions.contains {
                ($0["uploadEvent"] as? [String: Any])?["state"] as? String == "success"
            }
            archives.append(Archive(
                index: index,
                app: properties?["CFBundleIdentifier"] as? String ?? info?["Name"] as? String ?? item.title,
                version: properties?["CFBundleShortVersionString"] as? String,
                build: properties?["CFBundleVersion"] as? String,
                created: info?["CreationDate"] as? Date ?? item.date ?? .distantPast,
                uploaded: uploaded
            ))
        }
        var result = items
        for group in Dictionary(grouping: archives, by: \.app).values {
            let sorted = group.sorted { $0.created > $1.created }
            for (position, archive) in sorted.enumerated() {
                let item = items[archive.index]
                var parts: [String] = []
                if let version = archive.version {
                    parts.append(archive.build.map {
                        String(localized: "Version \(version) (\($0))",
                               comment: "Xcode archive detail; first %@ is the app version, second %@ the build number")
                    } ?? String(localized: "Version \(version)", comment: "Xcode archive detail; %@ is the app version"))
                }
                parts.append(String(localized: "archived \(archive.created.formatted(date: .abbreviated, time: .shortened))",
                                    comment: "Fact in an Xcode archive's detail line; %@ is a date and time"))
                if archive.uploaded {
                    parts.append(String(localized: "uploaded to Apple", comment: "Fact in an Xcode archive's detail line"))
                }
                let level: Safety
                if position == 0 {
                    level = .risky
                    parts.append(String(localized: "newest archive of this app: its build and crash symbols exist only here",
                                        comment: "Fact in an Xcode archive's detail line"))
                } else {
                    level = .askAI
                    let sameVersion = archive.version != nil
                        && sorted[..<position].contains { $0.version == archive.version }
                    parts.append(sameVersion
                        ? String(localized: "a newer build of this version exists", comment: "Fact in an Xcode archive's detail line")
                        : String(localized: "the build comes back from its git tag; only crash symbols for this build are lost",
                                 comment: "Fact in an Xcode archive's detail line"))
                }
                var labeled = CleanupItem(
                    id: item.id, category: item.category, title: item.title,
                    badge: position == 0 ? String(localized: "Newest", comment: "Badge of the newest Xcode archive of an app") : nil,
                    detail: parts.joined(separator: " · "), size: item.size, removal: item.removal, date: archive.created
                )
                labeled.safetyLevel = level
                result[archive.index] = labeled
            }
        }
        return result
    }

    static func resolved(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }

    /// The Xcode that `xcode-select` points to, as an app path.
    static func selectedXcode() async -> String? {
        guard let output = try? await ProcessRunner.run("/usr/bin/xcode-select", ["-p"], timeout: .seconds(10)),
              output.succeeded else { return nil }
        let developer = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = developer.range(of: ".app/") else { return nil }
        return String(developer[..<range.lowerBound]) + ".app"
    }
}

/// iPhone and iPad backups made by Finder (named from their Info.plist) and downloaded iOS updates.
struct DevicesScanner: Scanner {
    var categories: [CategoryID] { [.devices] }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        var output = await LocationScanner(category: .devices, locations: KnownLocations.devices).scan(context)[.devices]
            ?? ScanOutput()
        let backupsFolder = context.homePath("Library/Application Support/MobileSync/Backup")
        if FileInfo.exists(backupsFolder), FileInfo.children(backupsFolder).isEmpty, !context.fullDiskAccess {
            output.notes.append(String(localized: "Device backups can be listed only with Full Disk Access.",
                                       comment: "Note in the iPhone & iPad category"))
        }
        let backups = FileInfo.children(backupsFolder).filter { !$0.hasPrefix(".") }.map { backupsFolder + "/" + $0 }
        let items: [CleanupItem?] = await Concurrency.map(backups, limit: 2) { path -> CleanupItem? in
            let measurement = FileSizer.measure(path, progress: context.progress)
            // Removed only as the scan saw it: a new backup into the same folder since then keeps it.
            guard measurement.rootReadable, let target = FileTarget(watching: path) else { return nil }
            let info = NSDictionary(contentsOfFile: path + "/Info.plist")
            let name = info?["Device Name"] as? String ?? info?["Display Name"] as? String
                ?? String(localized: "Device backup", comment: "Title of an iPhone or iPad backup without a device name")
            let version = info?["Product Version"] as? String
            let date = info?["Last Backup Date"] as? Date ?? FileInfo.modificationDate(path)
            return CleanupItem(
                id: path,
                category: .devices,
                title: name,
                badge: String(localized: "Backup", comment: "Badge of an iPhone or iPad backup"),
                detail: (version.map { "iOS \($0) · " } ?? "")
                    + (date.map {
                        String(localized: "backed up \($0.formatted(date: .abbreviated, time: .omitted))",
                               comment: "Fact in a device backup's detail line; %@ is a date")
                    } ?? String(localized: "backup", comment: "Device backup detail when its date is unknown")),
                size: measurement.bytes,
                removal: .trash([target]),
                date: date
            )
        }
        output.items = (output.items + items.compactMap { $0 }).sorted { $0.size > $1.size }
        return [.devices: output]
    }
}

/// Top-level items of Downloads added `oldDownloadDays` or more ago. Installers and large files have their own
/// categories, so the same file never shows twice.
struct OldDownloadsScanner: Scanner {
    var categories: [CategoryID] { [.oldDownloads] }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        let downloads = context.homePath("Downloads")
        let cutoff = context.now.addingTimeInterval(-Double(ScanContext.oldDownloadDays) * 86_400)
        let candidates: [(path: String, added: Date)] = FileInfo.children(downloads).compactMap { name in
            guard !name.hasPrefix("."),
                  !InstallersScanner.extensions.contains((name as NSString).pathExtension.lowercased()) else { return nil }
            let path = downloads + "/" + name
            let added = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.addedToDirectoryDateKey]))?
                .addedToDirectoryDate ?? FileInfo.modificationDate(path)
            guard let added, added < cutoff else { return nil }
            return (path, added)
        }
        let items: [CleanupItem?] = await Concurrency.map(candidates.map(\.path)) { path -> CleanupItem? in
            var info = stat()
            guard lstat(path, &info) == 0 else { return nil }
            let isFile = (info.st_mode & S_IFMT) == S_IFREG
            if isFile, info.st_size >= ScanContext.largeFileThreshold { return nil }
            let measurement = FileSizer.measure(path, progress: context.progress)
            guard measurement.rootReadable, let target = FileTarget(watching: path) else { return nil }
            let added = candidates.first { $0.path == path }?.added
            return CleanupItem(
                id: path,
                category: .oldDownloads,
                title: (path as NSString).lastPathComponent,
                badge: isFile ? nil : String(localized: "Folder", comment: "Badge of a folder in Old Downloads"),
                detail: "~/Downloads" + (added.map {
                    " · " + String(localized: "added \($0.relativeDescription)",
                                   comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
                } ?? ""),
                size: measurement.bytes,
                removal: .trash([target]),
                date: added
            )
        }
        var output = ScanOutput(items: items.compactMap { $0 }.sorted { $0.size > $1.size })
        if FileInfo.isDirectory(downloads), (try? FileManager.default.contentsOfDirectory(atPath: downloads)) == nil {
            output.notes.append(String(localized: "Downloads couldn't be read. Allow access when macOS asks.",
                                       comment: "Note in Old Downloads; Downloads is the folder"))
        }
        return [.oldDownloads: output]
    }
}
