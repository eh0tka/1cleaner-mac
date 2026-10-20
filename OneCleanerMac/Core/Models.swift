import Foundation

enum CleanerGroup: String, CaseIterable, Sendable {
    case developer, everyday

    var title: String {
        self == .developer
            ? String(localized: "Developer",
                comment: "Sidebar group of developer cleanup categories (Xcode, Docker, ...)")
            : String(localized: "Everyday",
                comment: "Sidebar group of everyday cleanup categories (apps, caches, Downloads, ...)")
    }
    var categories: [CategoryID] { CategoryID.allCases.filter { $0.group == self } }
}

enum CategoryID: String, CaseIterable, Identifiable, Sendable {
    case projects, worktrees, xcode, simulators, android, packageCaches, editors, docker, aiModels, aiAgents
    case apps, leftovers, appCaches, logs, browserCaches, installers, oldDownloads, temporary, largeFiles, duplicates
    case devices, trash

    var id: String { rawValue }

    var group: CleanerGroup {
        switch self {
        case .projects, .worktrees, .xcode, .simulators, .android, .packageCaches, .editors, .docker, .aiModels,
             .aiAgents: .developer
        case .apps, .leftovers, .appCaches, .logs, .browserCaches, .installers, .oldDownloads, .temporary, .largeFiles,
             .duplicates, .devices, .trash: .everyday
        }
    }

    var title: String {
        switch self {
        case .projects: String(localized: "Project Builds",
            comment: "Category: build folders (node_modules, build outputs) inside the person's projects")
        case .worktrees: String(localized: "Git Worktrees",
            comment: "Category: extra working copies of git repositories made with `git worktree add`")
        case .xcode: "Xcode"
        case .simulators: String(localized: "Simulators", comment: "Category: iOS simulator devices and runtimes")
        case .android: "Android"
        case .packageCaches: String(localized: "Package Caches",
            comment: "Category: download caches of npm, Homebrew, pip, CocoaPods and similar tools")
        case .editors: String(localized: "Editors",
            comment: "Category: caches of code editors (VS Code, Cursor, JetBrains IDEs)")
        case .docker: "Docker"
        case .aiModels: String(localized: "AI Models",
            comment: "Category: local AI models (Ollama, LM Studio, Hugging Face)")
        case .aiAgents: String(localized: "AI Agents",
            comment: "Category: data kept by AI coding agents (Claude, Codex, Cursor, ...)")
        case .apps: String(localized: "Applications",
            comment: "Category: installed apps that can be removed with their data")
        case .leftovers: String(localized: "Removed Apps' Leftovers",
            comment: "Category: data left in the Library by apps that are no longer installed")
        case .appCaches: String(localized: "App Caches", comment: "Category: caches apps keep in the Library")
        case .logs: String(localized: "Logs", comment: "Category: diagnostic logs and crash reports")
        case .browserCaches: String(localized: "Browser Caches",
            comment: "Category: cached web pages and images of browsers")
        case .installers: String(localized: "Installers",
            comment: "Category: disk images and installer packages in Downloads and Desktop")
        case .oldDownloads: String(localized: "Old Downloads",
            comment: "Category: files that have been in Downloads for a long time")
        case .temporary: String(localized: "Temporary Files",
            comment: "Category: temporary files in /tmp and temp folders")
        case .largeFiles: String(localized: "Large Files", comment: "Category: large files in the home folder")
        case .duplicates: String(localized: "Duplicates",
            comment: "Category: exact copies of the same file in the home folder")
        case .devices: String(localized: "iPhone & iPad",
            comment: "Category: iPhone and iPad backups and downloaded iOS updates")
        case .trash: String(localized: "Trash", comment: "Category: the macOS Trash")
        }
    }

    var systemImage: String {
        switch self {
        case .projects: "folder.badge.gearshape"
        case .worktrees: "arrow.triangle.branch"
        case .xcode: "hammer"
        case .simulators: "iphone"
        case .android: "cpu"
        case .packageCaches: "archivebox"
        case .editors: "chevron.left.forwardslash.chevron.right"
        case .docker: "shippingbox"
        case .aiModels: "brain"
        case .aiAgents: "sparkles.rectangle.stack"
        case .apps: "square.grid.2x2"
        case .leftovers: "puzzlepiece.extension"
        case .appCaches: "square.stack.3d.up"
        case .logs: "doc.text"
        case .browserCaches: "globe"
        case .installers: "arrow.down.app"
        case .oldDownloads: "clock.arrow.circlepath"
        case .temporary: "hourglass"
        case .largeFiles: "doc.zipper"
        case .duplicates: "doc.on.doc"
        case .devices: "ipad.and.iphone"
        case .trash: "trash"
        }
    }

    /// What the category holds and what removing it means, shown above its list.
    var explanation: String {
        switch self {
        case .projects:
            String(localized: """
                node_modules, build outputs and virtual environments inside your projects. npm, Gradle, Xcode or \
                SwiftPM rebuild them on the next build, which takes time and sometimes internet. Each row shows when \
                its project last changed.
                """, comment: "Explanation above the Project Builds list")
        case .worktrees:
            String(localized: """
                Extra working copies of your git repositories, grouped by repository, often left by AI agents and \
                parallel branches. Removing one moves its folder to the Trash; its branch and commits stay in the \
                repository. Changes not committed in it, and files git ignores there (like .env), go with it. The \
                main copy of a repository is never listed.
                """, comment: "Explanation above the Git Worktrees list")
        case .xcode:
            String(localized: """
                DerivedData, caches, previews and device support files are rebuilt automatically. Archives hold your \
                uploaded builds and the symbols that make their crash reports readable. An old archive's build comes \
                back from its git tag, but not its crash symbols; the newest archive of each app is marked Risky.
                """, comment: "Explanation above the Xcode list. Risky is the safety label (may lose data).")
        case .simulators:
            String(localized: """
                Device: one virtual iPhone or iPad with its apps and data. Removing it keeps its iOS; a new one is \
                created in seconds (agents and Xcode do it themselves). Runtime: an iOS version itself, shared by \
                its devices. Removing it stops those devices until you download that iOS again. Xcode removes both \
                for good, they don't go to the Trash. Running simulators can't be removed.
                """,
                comment: "Explanation above the Simulators list. Device: a virtual iPhone/iPad. Runtime: an iOS version.")
        case .android:
            String(localized: """
                Gradle caches and downloads come back on the next build. Emulators and system images are kept unless \
                you select them.
                """, comment: "Explanation above the Android list")
        case .packageCaches:
            String(localized: """
                Download caches of npm, Yarn, Homebrew, pip, CocoaPods and other tools. They are downloaded again \
                when needed. The Maven repository, pnpm store and browser test downloads take longer to get back.
                """, comment: "Explanation above the Package Caches list. Tool names stay as they are.")
        case .editors:
            String(localized: "Caches of VS Code, Cursor and JetBrains IDEs. Settings, extensions and projects stay.",
                comment: "Explanation above the Editors list")
        case .docker:
            String(localized: """
                Stopped containers, images no running container uses, build cache and volumes no container uses. \
                Docker removes them for good, they don't go to the Trash. Check volumes carefully: they can hold \
                databases.
                """, comment: "Explanation above the Docker list")
        case .aiModels:
            String(localized: """
                Local AI models from Ollama, LM Studio and Hugging Face. They are often many gigabytes to download \
                again, so keep the ones you still use.
                """, comment: "Explanation above the AI Models list")
        case .aiAgents:
            String(localized: """
                What AI coding agents keep on this Mac: Claude, ChatGPT and Codex, Cursor, Antigravity and Gemini, \
                Qwen, Windsurf, Kiro, Trae, Cline and others. Session histories are what "resume" uses; anything \
                changed in the last day is locked. Live databases and settings are never offered.
                """,
                comment: "Explanation above the AI Agents list. Keep \"resume\" (the agents' command) in English.")
        case .apps:
            String(localized: """
                Remove an app together with its own data in your Library: settings, history, caches and login \
                agents, matched by the app's identifier. That data is what the app works with, so removing it resets \
                the app. Hover a row to see every path. Apple apps and running apps aren't offered; apps installed \
                for all users may need Finder to remove.
                """, comment: "Explanation above the Applications (uninstaller) list")
        case .leftovers:
            String(localized: """
                Settings, caches and data in your Library from apps that are no longer installed, grouped by app \
                identifier. If you plan to install an app again and want its settings back, keep its row. Not shown: \
                leftovers of a vendor whose other apps are still installed (vendors share helpers) and anything \
                changed in the last \(LeftoversScanner.recentDays) days (something still uses it).
                """,
                comment: "Explanation above the Removed Apps' Leftovers list. The placeholder is a number of days.")
        case .appCaches:
            String(localized: """
                Temporary data apps keep to work faster. Apps recreate it; quit them before cleaning. Leave Apple \
                system caches (com.apple.…) unless you know what they hold.
                """, comment: "Explanation above the App Caches list")
        case .logs:
            String(localized: "Diagnostic logs and crash reports of apps.", comment: "Explanation above the Logs list")
        case .browserCaches:
            String(localized: "Cached pages and images. Cookies, history, passwords and open tabs are not touched.",
                comment: "Explanation above the Browser Caches list")
        case .installers:
            String(localized: "Disk images and installer packages in Downloads and Desktop. Keep the ones you need offline.",
                comment: "Explanation above the Installers list")
        case .oldDownloads:
            String(localized: """
                Files and folders that have been in Downloads for \(ScanContext.oldDownloadDays) days or more. \
                Installers and files of \(ScanContext.largeFileThreshold.formattedBytes)+ are listed in their own \
                categories.
                """,
                comment: "Explanation above the Old Downloads list. Placeholders: days; a file size (\"200 MB\").")
        case .temporary:
            String(localized: """
                Temporary files apps and tools left in /tmp and your macOS temp folder, plus your own temp folders \
                (~/tmp, ~/temp). Only items where nothing changed for days are shown, so running builds and agent \
                sessions stay out.
                """,
                comment: "Explanation above the Temporary Files list. Keep /tmp, ~/tmp, ~/temp as they are.")
        case .largeFiles:
            String(localized: """
                Files of \(ScanContext.largeFileThreshold.formattedBytes) or more in your home folder. Review each \
                one before you select it.
                """,
                comment: "Explanation above the Large Files list. The placeholder is a file size (\"200 MB\").")
        case .duplicates:
            String(localized: """
                Files of \(DuplicateFinder.minimumSize.formattedBytes) or more that have exact copies in your home \
                folder. Open a file to see every copy and choose which to remove; one copy always stays. Copies that \
                already share space on the disk aren't shown, since removing them frees nothing.
                """,
                comment: "Explanation above the Duplicates list. The placeholder is a file size (\"1 MB\").")
        case .devices:
            String(localized: """
                iPhone and iPad backups made by Finder, and downloaded iOS updates. A backup may be the only copy of \
                a device's data: remove it only if you have a newer one or iCloud Backup.
                """, comment: "Explanation above the iPhone & iPad list. iCloud Backup is Apple's feature name.")
        case .trash:
            String(localized: "Files in the Trash still take space until the Trash is emptied.",
                comment: "Explanation above the Trash list")
        }
    }
}

/// Identity of a file system object at scan time; cleanup refuses an object that was replaced since.
struct FileTarget: Hashable, Sendable {
    /// Length and modification time of a file whose content matters (a duplicate copy): edited in place it keeps
    /// its inode, so the removal checks these too. Not the status-change time: opening a download changes that
    /// (macOS updates its attributes), and opening isn't a change.
    struct ContentStamp: Hashable, Sendable {
        let size: Int64
        let modified: Int64

        init(_ info: stat) {
            size = Int64(info.st_size)
            modified = Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
        }
    }

    let path: String
    let device: Int32
    let inode: UInt64
    private(set) var content: ContentStamp?
    /// Every file inside a folder of the person's own (an old download), as the scan saw it.
    private(set) var tree: Mover.Fingerprint?
    /// A session history or checkpoints: not removed while anything inside changed in the last day.
    var quietForADay = false
    /// A git worktree: not removed while its git index or any of its files outside dependency and build folders
    /// changed in the last day (`ProjectScanner.newestChange(inWorkingCopy:)`).
    var projectQuietForADay = false
    /// A git worktree's `locked` file (`git worktree lock`): while it exists, the worktree isn't removed.
    var gitLockFile: String?
    /// Apps (bundle identifiers or lowercased names) that use this path: it isn't removed while one of them runs.
    var usedWhileRunning: [String] = []

    init?(path: String) {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        self.path = path
        device = info.st_dev
        inode = info.st_ino
    }

    /// The person's own file or folder (installers, old downloads, large files): removed only as the scan saw it, so a
    /// file edited since, or a folder something was saved into, stays.
    init?(watching path: String) {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        self.path = path
        device = info.st_dev
        inode = info.st_ino
        if (info.st_mode & S_IFMT) == S_IFDIR {
            // A folder that can't be read through can't be checked later, so it isn't offered.
            let print = Mover.fingerprint(path)
            guard print.unreadable == 0 else { return nil }
            tree = print
        } else {
            content = ContentStamp(info)
        }
    }

    /// A file that must still hold the content the scan compared: `expected` is its stamp and `device`/`inode` its
    /// identity from before the comparison; nil when the file changed or was replaced since then.
    init?(path: String, expected: ContentStamp, device: Int32, inode: UInt64) {
        var info = stat()
        guard lstat(path, &info) == 0, ContentStamp(info) == expected, info.st_dev == device, info.st_ino == inode
        else { return nil }
        self.path = path
        self.device = device
        self.inode = inode
        content = expected
    }
}

enum DockerOperation: Hashable, Sendable {
    case container(String)
    /// An image and the stopped containers created from it, removed together (containers first). `references`:
    /// its `repository:tag` names; one tagged in two repositories goes only by its names.
    case image(String, stoppedContainers: [String], references: [String] = [])
    /// A volume by name and its creation time at the scan: a volume made again under the same name isn't the one
    /// that was listed.
    case volume(String, created: String)
    case buildCache
}

enum Removal: Hashable, Sendable {
    case trash([FileTarget])
    case docker(DockerOperation)
    /// `lastUsed`: simctl's "last used" mark at the scan; a device booted since then has new data and stays.
    case simulatorDevice(udid: String, lastUsed: String? = nil)
    case simulatorRuntime(id: String)
    /// The Trash itself: emptied with its own button, never through selection.
    case emptyTrash

    /// Removed by the tool itself, without a way back.
    var isPermanent: Bool {
        switch self {
        case .trash, .emptyTrash: false
        case .docker, .simulatorDevice, .simulatorRuntime: true
        }
    }

    /// Cleanup order: files first, then containers before the images they use, then simulators.
    var order: Int {
        switch self {
        case .trash: 0
        case .docker(.container): 1
        case .docker(.image): 2
        case .docker(.volume): 3
        case .docker(.buildCache): 4
        case .simulatorDevice: 5
        case .simulatorRuntime: 6
        case .emptyTrash: 7
        }
    }

    var paths: [String] {
        if case .trash(let targets) = self { return targets.map(\.path) }
        return []
    }
}

struct CleanupItem: Identifiable, Hashable, Sendable {
    /// Stable across scans: a path, or a tool identifier such as `docker:image:<id>`. Also the Safe List key.
    let id: String
    let category: CategoryID
    let title: String
    /// Short tag shown next to the title, e.g. "node_modules" or "Unavailable".
    var badge: String?
    let detail: String
    let size: Int64
    let removal: Removal
    /// Why the item is shown but can't be selected (a running simulator, a runtime bundled with Xcode).
    var lockedReason: String?
    var date: Date?
    /// The project (repository root when there is one) a build folder belongs to, for "Add Project to Safe List".
    var projectPath: String?
    /// Signs of personal data found inside (e.g. "Login Data", "Bookmarks", "databases"); shown and used for
    /// the safety hint of leftovers.
    var userData: [String] = []
    /// A level set by the scanner itself (AI Agents rows); see `CleanupItem.safety`.
    var safetyLevel: Safety?
    /// Duplicates: every copy of one file shares this key (the oldest copy's path); one copy always stays.
    var duplicateGroup: String?
    /// Duplicates: the oldest copy of its set.
    var isOldestCopy = false

    var isSelectable: Bool { lockedReason == nil && removal != .emptyTrash }
    var revealPath: String? { removal.paths.first }
    /// A git worktree stays where git recorded it: moved elsewhere, its repository would lose track of it.
    var canMoveToAnotherDisk: Bool { revealPath != nil && lockedReason == nil && category != .worktrees }
}

struct ScanOutput: Sendable {
    var items: [CleanupItem] = []
    var notes: [String] = []
    /// Neutral information shown above the list, e.g. where Docker's space goes.
    var summary: String?
}

struct CategoryResult: Sendable {
    enum State: Sendable { case idle, scanning, done }

    var state: State = .idle
    var items: [CleanupItem] = []
    var notes: [String] = []
    var summary: String?

    /// What cleaning everything here can free. Duplicates: one copy of each set always stays, so it doesn't count.
    var totalSize: Int64 {
        var kept: [String: Int64] = [:]
        for item in items {
            if let group = item.duplicateGroup { kept[group] = max(kept[group] ?? 0, item.size) }
        }
        return items.reduce(0) { $0 + $1.size } - kept.values.reduce(0, +)
    }
}
