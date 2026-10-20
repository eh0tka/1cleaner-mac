import CoreServices
import Darwin
import Foundation

/// One walk over the scan folders finds project build folders, large files and duplicates.
///
/// A build folder counts only next to the file that proves its tool (`node_modules` next to `package.json`,
/// `target` next to `Cargo.toml`, ...), so a folder that merely has the same name is never offered.
/// The walk never enters a found build folder, `.git`, `~/Library`, tool homes or app bundles.
struct ProjectScanner: Scanner {
    var categories: [CategoryID] { [.projects, .worktrees, .largeFiles, .duplicates] }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        var walk = Walk(context: context)
        for root in Self.distinctRoots(context.roots) {
            if Task.isCancelled { break }
            context.progress.setFolder(PathDisplay.abbreviated(root))
            walk.run(root)
        }
        let unreadable = walk.unreadable
        let artifacts = walk.artifacts
        let largeFiles = walk.largeFiles
        let duplicates = await DuplicateFinder.items(walk.duplicateCandidates, progress: context.progress)
        let worktrees = await WorktreeFinder.items(repositories: walk.mainRepositories, context: context)

        // Last activity per project: newest change among its own files (never inside build folders) and in its
        // repository, so a quiet module of an active repository isn't treated as abandoned.
        let projectRoots = Array(Set(artifacts.map(\.project)))
        let projectInfos: [ProjectInfo] = await Concurrency.map(projectRoots, limit: 6) { project in
            Self.projectInfo(project, home: context.home)
        }
        let projectByPath = Dictionary(projectInfos.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })

        let projectItems: [CleanupItem?] = await Concurrency.map(artifacts, limit: 4) { artifact -> CleanupItem? in
            let measurement = FileSizer.measure(artifact.path, progress: context.progress)
            guard measurement.rootReadable, measurement.bytes > 0, let target = FileTarget(path: artifact.path) else {
                return nil
            }
            let project = projectByPath[artifact.project]
            let lastActivity = project?.lastActivity
            let root = project?.root ?? artifact.project
            // A `build` folder can hold scripts or icons someone committed there by mistake:
            // with files git tracks inside it's Ask AI, and the row says how many.
            let tracked = (artifact.path as NSString).lastPathComponent == "build" ? await Self.trackedFiles(in: artifact.path) : 0
            var item = CleanupItem(
                id: artifact.path,
                category: .projects,
                title: project?.title ?? (artifact.project as NSString).lastPathComponent,
                badge: artifact.name,
                detail: PathDisplay.abbreviated(artifact.path)
                    + (lastActivity.map {
                        " · " + String(localized: "project changed \($0.relativeDescription)",
                                       comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
                    } ?? "")
                    + (tracked > 0
                        ? " · " + String(localized: "\(tracked) files in it are tracked by git",
                                         comment: "Fact in a Project Builds row: the build folder holds files committed to git")
                        : ""),
                size: measurement.bytes,
                removal: .trash([target]),
                date: lastActivity,
                // Never the home folder itself (`npm install` run in ~): adding it to the Safe List would hide everything.
                projectPath: root == context.home ? nil : root
            )
            if tracked > 0 { item.safetyLevel = .askAI }
            return item
        }

        let largeItems: [CleanupItem] = largeFiles.compactMap { file in
            guard let target = FileTarget(watching: file.path) else { return nil }
            let lastOpened = Self.lastOpened(file.path) ?? FileInfo.modificationDate(file.path)
            return CleanupItem(
                id: file.path,
                category: .largeFiles,
                title: (file.path as NSString).lastPathComponent,
                detail: PathDisplay.abbreviated((file.path as NSString).deletingLastPathComponent)
                    + (lastOpened.map {
                        " · " + String(localized: "opened \($0.relativeDescription)",
                                       comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
                    } ?? ""),
                size: file.size,
                removal: .trash([target]),
                date: lastOpened
            )
        }

        var projects = ScanOutput(items: projectItems.compactMap { $0 }.sorted { $0.size > $1.size })
        var large = ScanOutput(items: largeItems.sorted { $0.size > $1.size })
        if unreadable > 0 {
            let note = String(localized: """
                \(unreadable) folders couldn't be read. Allow access when macOS asks, or give 1Cleaner Full Disk Access.
                """, comment: "Note above Projects and Large Files; %lld is the number of folders")
            projects.notes.append(note)
            large.notes.append(note)
        }
        return [.projects: projects, .worktrees: worktrees, .largeFiles: large, .duplicates: ScanOutput(items: duplicates)]
    }

    /// Drops scan folders inside other scan folders.
    static func distinctRoots(_ roots: [String]) -> [String] {
        let sorted = roots.map { ($0 as NSString).standardizingPath }.sorted()
        var result: [String] = []
        for root in sorted where !result.contains(where: { root == $0 || root.hasPrefix($0 + "/") }) {
            result.append(root)
        }
        return result.filter(FileInfo.isDirectory)
    }

    struct ProjectInfo: Sendable {
        let path: String
        /// The enclosing repository, or the project folder itself.
        let root: String
        /// Repository name, plus the module path inside it: "my-app › expo-app/android/app".
        let title: String
        let lastActivity: Date?
    }

    static func projectInfo(_ project: String, home: String) -> ProjectInfo {
        var activity = lastActivity(of: project)
        var title = (project as NSString).lastPathComponent
        var root = project
        // The nearest enclosing git repository, up to six levels up and never the home folder itself.
        var candidate = project
        for _ in 0..<6 {
            if candidate == home || candidate.count <= home.count { break }
            if FileInfo.exists(candidate + "/.git") {
                root = candidate
                if candidate != project {
                    let name = (candidate as NSString).lastPathComponent
                    title = name + " › " + project.dropFirst(candidate.count + 1)
                    for date in gitDates(candidate) { activity = max(activity ?? date, date) }
                }
                break
            }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        return ProjectInfo(path: project, root: root, title: title, lastActivity: activity)
    }

    /// When git last touched the repository: its index and HEAD. In a worktree `.git` is a file pointing at the
    /// worktree's own folder inside the main repository (`gitdir: …/.git/worktrees/<name>`), which holds them.
    static func gitDates(_ repository: String) -> [Date] {
        var gitFolder = repository + "/.git"
        if !FileInfo.isDirectory(gitFolder),
           let text = try? String(contentsOfFile: gitFolder, encoding: .utf8),
           let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir: ") }) {
            let target = String(line.dropFirst("gitdir: ".count)).trimmingCharacters(in: .whitespaces)
            gitFolder = target.hasPrefix("/") ? target : repository + "/" + target
        }
        return [gitFolder + "/index", gitFolder + "/HEAD", repository + "/.git"].compactMap(FileInfo.modificationDate)
    }

    /// Newest modification among the project's files up to three levels deep (outside build folders, hidden
    /// folders and dependencies) and its git index, which changes with every git status or commit.
    static func lastActivity(of project: String) -> Date? {
        var newest = FileInfo.modificationDate(project)
        for date in gitDates(project) { newest = max(newest ?? date, date) }
        var visited = 0
        FileSizer.walk(project) { entry in
            visited += 1
            if visited > 5_000 { return .stop }
            let level = Int(entry.pointee.fts_level)
            let info = Int32(entry.pointee.fts_info)
            if info == FTS_D, level > 0 {
                let name = entry.name
                if name.hasPrefix(".") || Walk.buildFolderNames.contains(name) || level >= 3 { return .skip }
            }
            if info == FTS_F, let stat = entry.pointee.fts_statp?.pointee {
                let date = Date(timeIntervalSince1970: TimeInterval(stat.st_mtimespec.tv_sec))
                newest = max(newest ?? date, date)
            }
            return .continue
        }
        return newest
    }

    /// Newest change anywhere in a working copy (a git worktree), at any depth and in hidden folders too: an agent
    /// may be editing `src/a/b/c/file` without touching git. Build and dependency folders proven by their tool's file
    /// (`Walk.isBuildFolder`) don't count, and neither does a `.git` folder. `complete` is false when a folder couldn't be read or the walk
    /// passed `limit` entries: then nobody can say the copy is quiet. `holdsRepository`: a submodule or another
    /// repository is checked out inside (a `.git` below the top), whose own changes the copy's git status can't show;
    /// `holdsClone`: one of them is a repository of its own (a `.git` folder), whose commits the main one doesn't have.
    static func newestChange(inWorkingCopy folder: String, limit: Int = 1_000_000)
        -> (date: Date?, complete: Bool, holdsRepository: Bool, holdsClone: Bool) {
        var newest = lastActivity(of: folder)
        var visited = 0
        var complete = true
        var holdsRepository = false
        var holdsClone = false
        let whole = FileSizer.walk(folder) { entry in
            visited += 1
            if visited > limit || Task.isCancelled {
                complete = false
                return .stop
            }
            let info = Int32(entry.pointee.fts_info)
            if info == FTS_DNR || info == FTS_ERR || info == FTS_NS { complete = false }
            if entry.pointee.fts_level > 1, entry.name == ".git" {
                holdsRepository = true
                if info == FTS_D { holdsClone = true }
            }
            // A bare repository (`backup.git` with its own HEAD and objects) is one of its own too.
            if info == FTS_D, entry.pointee.fts_level > 0, entry.name.hasSuffix(".git"), entry.name != ".git" {
                let path = entry.path
                if FileInfo.exists(path + "/HEAD"), FileInfo.isDirectory(path + "/objects") {
                    holdsRepository = true
                    holdsClone = true
                }
            }
            // Only a folder proven to be build output or dependencies is skipped: `src/build` may hold sources.
            if info == FTS_D, entry.pointee.fts_level > 0 {
                let name = entry.name
                if name == ".git" || name == "node_modules" { return .skip }
                if Walk.buildFolderNames.contains(name) {
                    let path = entry.path
                    if Walk.isBuildFolder(name: name, path: path, parent: (path as NSString).deletingLastPathComponent) {
                        return .skip
                    }
                }
            }
            if info == FTS_D || info == FTS_F, let stat = entry.pointee.fts_statp?.pointee {
                // A file's status-change time too: an edit that puts the modification time back still shows.
                let seconds = info == FTS_F ? max(stat.st_mtimespec.tv_sec, stat.st_ctimespec.tv_sec) : stat.st_mtimespec.tv_sec
                let date = Date(timeIntervalSince1970: TimeInterval(seconds))
                newest = max(newest ?? date, date)
            }
            return .continue
        }
        // Nothing read at all (the folder couldn't be opened) isn't quiet either.
        return (newest, complete && whole && visited > 0, holdsRepository, holdsClone)
    }

    /// Files inside `folder` that its repository tracks (`git ls-files`, which reads only git's index, run without
    /// the repository's own programs); 0 outside a repository or without git.
    static func trackedFiles(in folder: String) async -> Int {
        guard let git = WorktreeFinder.git, let output = try? await ProcessRunner.run(
            git, WorktreeFinder.gitSafety + ["-C", (folder as NSString).deletingLastPathComponent, "ls-files", "-z", "--",
                                             (folder as NSString).lastPathComponent],
            timeout: .seconds(30), extraEnvironment: ["GIT_OPTIONAL_LOCKS": "0"]
        ), output.succeeded else { return 0 }
        return output.stdout.split(separator: "\0").count
    }

    /// Spotlight's "Last opened" date, when Spotlight indexed the file.
    static func lastOpened(_ path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

private struct Artifact: Sendable {
    let path: String
    let name: String
    let project: String
}

private struct LargeFile: Sendable {
    let path: String
    let size: Int64
}

private struct Walk {
    static let buildFolderNames: Set<String> = [
        "node_modules", ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular",
        ".build", "build", ".gradle", "target", "Pods", ".dart_tool", ".venv", "venv",
    ]

    /// Tool homes directly in the home folder: their contents are covered by Package Caches or are installed tools
    /// (global node packages, toolchains), never project builds.
    static let skippedHomeFolders: Set<String> = [
        "Library", ".Trash", ".npm", ".cache", ".gradle", ".cargo", ".rustup", ".m2", ".bun", ".nvm", ".pyenv",
        ".rbenv", ".local", ".vscode", ".cursor", ".windsurf", ".docker", ".android", ".cocoapods", ".swiftpm",
        ".yarn", ".pnpm-store", ".deno", ".volta", ".fnm", ".asdf", ".sdkman", ".gem", ".conda", ".oh-my-zsh",
        ".colima", ".lima", ".orbstack", ".expo", ".node-gyp", ".dartServer", ".pub-cache", ".gk", ".kube",
        ".ssh", ".gnupg", ".aws", ".config", "Applications",
    ]

    static let packageExtensions: Set<String> = [
        "app", "photoslibrary", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle", "logicx", "band",
        "framework", "bundle", "plugin", "kext", "xcarchive", "pvm", "vmwarevm", "utm", "sparsebundle",
        "photolibrary", "aplibrary", "migratedphotolibrary",
    ]

    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]

    /// What only Xcode writes into a build folder: its own build products, or a DerivedData folder put there by a
    /// script (`xcodebuild -derivedDataPath build`).
    static let xcodeBuildOutput: Set<String> = ["XCBuildData", "SharedPrecompiledHeaders", "EagerLinkingTBDs"]

    /// Other names count as Xcode's only with what Xcode puts inside them: a committed `build/Debug` with icons or
    /// a script named `Build` proves nothing.
    static func provesXcodeOutput(_ child: String, in folder: String) -> Bool {
        // Only folders: a file such as `meson.build` proves nothing.
        let path = folder + "/" + child
        guard FileInfo.isDirectory(path), !FileInfo.isSymbolicLink(path) else { return false }
        if xcodeBuildOutput.contains(child) || child.hasSuffix(".build") || child.hasSuffix(".noindex") { return true }
        let inside = FileInfo.children(path)
        // A DerivedData folder under any name (`-derivedDataPath build/ReleaseDerivedData`).
        if inside.contains("Build"), inside.contains("info.plist") || inside.contains("ModuleCache.noindex") { return true }
        switch child {
        case "Build":
            return inside.contains("Products") || inside.contains("Intermediates.noindex")
        case "DerivedData":
            return inside.contains("Build") || inside.contains("ModuleCache.noindex") || inside.contains("info.plist")
        case "SourcePackages":
            return inside.contains("checkouts") || inside.contains("artifacts") || inside.contains("repositories")
        case _ where child.hasSuffix(".xcframework"):
            // `xcodebuild -create-xcframework -output build/Foo.xcframework`.
            return inside.contains("Info.plist")
        default:
            // A configuration's products (`Debug`, `Release-iphoneos`, `Staging`): Xcode's product types, or a
            // command-line tool, which is a Mach-O file without an extension.
            let products = [".app", ".framework", ".xcframework", ".a", ".dylib", ".swiftmodule", ".dSYM", ".appex",
                            ".xctest", ".bundle"]
            return inside.contains { name in
                products.contains { name.hasSuffix($0) } || !name.contains(".") && isMachO(path + "/" + name)
            }
        }
    }

    /// A compiled program or library: a regular file whose first bytes are a Mach-O or universal-binary mark
    /// (never opened otherwise: a pipe would wait for a writer).
    private static func isMachO(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size >= 4 else { return false }
        let file = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard file >= 0 else { return false }
        defer { close(file) }
        // Still a regular file once open (it could have been swapped for a pipe in between).
        var opened = stat()
        guard fstat(file, &opened) == 0, (opened.st_mode & S_IFMT) == S_IFREG else { return false }
        var magic: UInt32 = 0
        guard read(file, &magic, 4) == 4 else { return false }
        return [0xfeedfacf, 0xfeedface, 0xcffaedfe, 0xcefaedfe, 0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca]
            .contains(magic)
    }

    let context: ScanContext
    var artifacts: [Artifact] = []
    var largeFiles: [LargeFile] = []
    var duplicateCandidates: [DuplicateFinder.File] = []
    var unreadable = 0
    /// Git repositories around the current path, outermost first. Duplicates inside a repository are project
    /// files (vendored code, assets) that the project needs at their paths, so they aren't offered.
    private var repositories: [String] = []
    /// Main repositories seen by the walk, for their worktrees.
    var mainRepositories: [String] = []
    private var foundPaths = Set<String>()

    init(context: ScanContext) {
        self.context = context
    }

    mutating func run(_ root: String) {
        var visited = 0
        let home = context.home
        // A scan folder inside a git repository (or the repository itself), also on another disk: its files are
        // the project's files. The home folder and / themselves don't count (a dotfiles repository in ~).
        var folder = root
        while folder != home, folder != "/", !folder.isEmpty {
            if FileInfo.exists(folder + "/.git") {
                repositories = [root]
                if FileInfo.isDirectory(folder + "/.git") { mainRepositories.append(folder) }
                break
            }
            folder = (folder as NSString).deletingLastPathComponent
        }
        FileSizer.walk(root) { entry in
            visited += 1
            if visited % 4096 == 0 {
                context.progress.add(entries: 4096)
                if Task.isCancelled { return .stop }
            }
            switch Int32(entry.pointee.fts_info) {
            case FTS_D:
                guard entry.pointee.fts_level > 0 else { return .continue }
                return visitDirectory(entry, home: home)
            case FTS_F:
                guard let stat = entry.pointee.fts_statp?.pointee, Int64(stat.st_size) >= DuplicateFinder.minimumSize else {
                    return .continue
                }
                let path = entry.path
                // Files inside hidden folders (~/.codex, project .git, ...) are tool data, not the person's files.
                let insideHidden = path.dropFirst(root.count).split(separator: "/").dropLast().contains { $0.hasPrefix(".") }
                guard !insideHidden, !KnownLocations.isInSyncedHomeFolder(path, home: home) else { return .continue }
                // SF_DATALESS: the file lives only in iCloud; reading it to compare would download it.
                if stat.st_flags & 0x4000_0000 == 0, !insideRepository(path) {
                    duplicateCandidates.append(DuplicateFinder.File(
                        path: path, size: Int64(stat.st_size), allocated: Int64(stat.st_blocks) * 512,
                        device: stat.st_dev, inode: stat.st_ino, stamp: FileTarget.ContentStamp(stat)
                    ))
                }
                // An iCloud-only file takes no space here, and moving it to the Trash removes it from iCloud.
                if Int64(stat.st_size) >= ScanContext.largeFileThreshold, stat.st_flags & 0x4000_0000 == 0,
                   !Self.installerExtensions.contains((path as NSString).pathExtension.lowercased()) {
                    largeFiles.append(LargeFile(path: path, size: Int64(stat.st_blocks) * 512))
                }
            case FTS_DNR, FTS_ERR:
                unreadable += 1
            default:
                break
            }
            return .continue
        }
        context.progress.add(entries: visited % 4096)
    }

    private mutating func insideRepository(_ path: String) -> Bool {
        while let last = repositories.last, !path.hasPrefix(last + "/") { repositories.removeLast() }
        return !repositories.isEmpty
    }

    private mutating func visitDirectory(_ entry: UnsafeMutablePointer<FTSENT>, home: String) -> FileSizer.WalkAction {
        let name = entry.name
        if name != ".git" {
            let inside = insideRepository(entry.path)
            if FileInfo.exists(entry.path + "/.git") {
                if !inside { repositories.append(entry.path) }
                // A main repository (its `.git` is a folder) lists its worktrees, wherever they are.
                if FileInfo.isDirectory(entry.path + "/.git") { mainRepositories.append(entry.path) }
            }
        }
        if name == ".git" || name == ".Trash" || name == ".Spotlight-V100" || name == ".fseventsd" { return .skip }
        if let ext = name.split(separator: ".").last, name.contains("."), !name.hasPrefix("."),
           Self.packageExtensions.contains(ext.lowercased()) {
            return .skip
        }
        let path = entry.path
        if context.safeFolders.contains(path) { return .skip }
        let parent = (path as NSString).deletingLastPathComponent
        // Go's downloaded modules (Package Caches), never the person's projects; ~/go/src may hold projects.
        if path == home + "/go/pkg" { return .skip }
        // Hidden folders in the home folder are tools' own data (~/.claude, ~/.gemini plugins with their
        // node_modules), never the person's projects; their files aren't listed anyway (`insideHidden`).
        if parent == home, name.hasPrefix(".") || Self.skippedHomeFolders.contains(name) { return .skip }
        // Also right in the home folder (`npm install` run in ~): never walked into package by package.
        if Self.buildFolderNames.contains(name) {
            if Self.isBuildFolder(name: name, path: path, parent: parent) {
                if foundPaths.insert(path).inserted {
                    artifacts.append(Artifact(path: path, name: name, project: parent))
                }
                return .skip
            }
            // A dependency folder that isn't a build folder here is still nothing to scan for projects.
            if name == "node_modules" { return .skip }
        }
        if entry.pointee.fts_level <= 2 { context.progress.setFolder(PathDisplay.abbreviated(path)) }
        return .continue
    }

    static func isBuildFolder(name: String, path: String, parent: String) -> Bool {
        func has(_ file: String) -> Bool { FileInfo.exists(parent + "/" + file) }
        func hasGradle() -> Bool {
            has("build.gradle") || has("build.gradle.kts") || has("settings.gradle") || has("settings.gradle.kts")
        }
        switch name {
        case "node_modules", ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular":
            return has("package.json")
        case ".build":
            return has("Package.swift")
        case "build":
            // Next to an Xcode project only with Xcode's own build output inside: some projects keep scripts,
            // entitlements or icons in a committed build folder.
            return hasGradle() || has("pubspec.yaml")
                || FileInfo.children(parent).contains { $0.hasSuffix(".xcodeproj") } && FileInfo.children(path).contains {
                    Self.provesXcodeOutput($0, in: path)
                }
        case ".gradle":
            return hasGradle()
        case "target":
            return has("Cargo.toml") || has("pom.xml")
        case "Pods":
            return has("Podfile")
        case ".dart_tool":
            return has("pubspec.yaml")
        case ".venv", "venv":
            return FileInfo.exists(path + "/pyvenv.cfg")
        default:
            return false
        }
    }
}
