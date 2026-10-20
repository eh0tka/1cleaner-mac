#if DEBUG
import Foundation

/// DEBUG `-demoData YES`: made-up but realistic results for website screenshots, so no real project, client or
/// account name of the developer's Mac appears. Paths don't exist, so nothing here can be cleaned (Remover checks
/// each path's device and inode). Stats and settings go to a separate defaults suite.
enum DemoData {
    static let suite = "app.antosha.onecleaner.mac.demo"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: "demoData") }

    static func defaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static let home = NSHomeDirectory()
    private static let now = Date()
    private static let GB: Int64 = 1_000_000_000
    private static let MB: Int64 = 1_000_000

    private static func ago(days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    // Details, badges and notes below use the same String(localized:) keys as the scanners, so screenshots in
    // every language share their translations. Made-up project, app and file names stay as they are.
    private static func changed(_ days: Double) -> String {
        String(localized: "changed \(ago(days: days).relativeDescription)",
               comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
    }

    private static func lastChanged(_ days: Double) -> String {
        String(localized: "last changed \(ago(days: days).relativeDescription)",
               comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
    }

    private static func used(_ days: Double) -> String {
        String(localized: "used \(ago(days: days).relativeDescription)",
               comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
    }

    private static func opened(_ days: Double) -> String {
        String(localized: "opened \(ago(days: days).relativeDescription)",
               comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
    }

    private static func keeps(_ runtime: String) -> String {
        String(localized: "removing it keeps \(runtime)",
               comment: "Fact in a simulator device's detail line; %@ is a runtime like iOS 17.5")
    }

    private static func cantRun() -> String {
        let reason = String(localized: "runtime is missing", comment: "Why a simulator device can't run, in parentheses")
        return String(localized: "can't run: its iOS is gone (\(reason))",
                      comment: "Fact in a simulator device's detail line; %@ is the reason from Xcode (English)")
    }

    private static func archiveDate(_ days: Double) -> String {
        String(localized: "archived \(ago(days: days).formatted(date: .abbreviated, time: .shortened))",
               comment: "Fact in an Xcode archive's detail line; %@ is a date and time")
    }

    private static func appDetail(_ app: Int64, _ data: Int64, places: Int, days: Double) -> String {
        String(localized: "App \(app.formattedBytes) + app data \(data.formattedBytes) in \(places) places",
               comment: "Uninstaller row detail; first %@ is the app's size, second %@ its data size, %lld the number of places")
            + " · " + opened(days)
    }

    private static func leftoverDetail(_ id: String, days: Double) -> String {
        id + " · " + lastChanged(days) + " · "
            + String(localized: "settings and caches only", comment: "Fact in a leftovers row's detail line")
    }

    private static func item(
        _ category: CategoryID, _ title: String, badge: String? = nil, path: String, detail: String? = nil,
        size: Int64, days: Double? = nil, safety: Safety? = nil, removal: Removal? = nil, locked: String? = nil,
        project: String? = nil, userData: [String] = []
    ) -> CleanupItem {
        let full = path.hasPrefix("/") ? path : home + "/" + path
        var result = CleanupItem(
            id: "demo:" + full, category: category, title: title, badge: badge,
            detail: detail ?? PathDisplay.abbreviated(full), size: size,
            removal: removal ?? .trash([FileTarget(demoPath: full)]), lockedReason: locked,
            date: days.map(ago(days:)), projectPath: project.map { home + "/" + $0 }, userData: userData
        )
        result.safetyLevel = safety
        return result
    }

    private static func build(_ name: String, _ project: String, _ title: String, size: Int64, days: Double) -> CleanupItem {
        let path = "Developer/\(project)/\(name)"
        return item(.projects, title, badge: name, path: path,
                    detail: "~/\(path) · " + String(localized: "project changed \(ago(days: days).relativeDescription)",
                                                    comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'"),
                    size: size, days: days, project: "Developer/\(project)")
    }

    /// A worktree of `repo` (under ~/Developer) at `path`, as WorktreeFinder lists it.
    private static func worktree(_ path: String, repo: String, branch: String?, size: Int64, days: Double,
                                 changes: Int = 0, locked: String? = nil) -> CleanupItem {
        let changed = String(localized: "changed \(ago(days: days).relativeDescription)",
                             comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
        let state = changes == 0
            ? String(localized: "everything committed", comment: "Fact in a Git Worktrees row: no uncommitted changes")
            : String(localized: "\(changes) files not committed",
                     comment: "Fact in a Git Worktrees row; %lld is a number of changed files")
        return item(.worktrees, (path as NSString).lastPathComponent,
                    badge: branch ?? String(localized: "No branch",
                                            comment: "Badge of a git worktree whose HEAD is detached (not on a branch)"),
                    path: path, detail: "~/\(path) · \(changed) · \(state)", size: size, days: days,
                    safety: changes == 0 ? .askAI : .risky, locked: locked, project: "Developer/\(repo)")
    }

    static func results() -> [CategoryID: CategoryResult] {
        var out: [CategoryID: [CleanupItem]] = [:]
        out[.worktrees] = [
            worktree(".cursor/worktrees/shop-web/abc12", repo: "shop-web", branch: "agent/checkout-fix",
                     size: 1_420 * MB, days: 18),
            worktree("Developer/shop-web/.claude/worktrees/new-search", repo: "shop-web", branch: "feature/search",
                     size: 980 * MB, days: 6, changes: 3),
            worktree(".codex/worktrees/shop-web-2", repo: "shop-web", branch: nil, size: 610 * MB, days: 40),
            worktree("Developer/image-resizer-avif", repo: "image-resizer", branch: "avif",
                     size: 2_240 * MB, days: 75),
            worktree("Developer/image-resizer-hotfix", repo: "image-resizer", branch: "hotfix/1.4.1",
                     size: 1_870 * MB, days: 0.2,
                     locked: String(localized: "Changed in the last day; a session may be running.",
                                    comment: "Why an AI agent's session history can't be selected")),
        ]
        out[.projects] = [
            build("target", "image-resizer", "image-resizer", size: 4_810 * MB, days: 140),
            build("node_modules", "shop-web", "shop-web", size: 1_920 * MB, days: 63),
            build(".next", "shop-web", "shop-web", size: 1_240 * MB, days: 63),
            build(".build", "weather-kit", "weather-kit", size: 1_610 * MB, days: 21),
            build("node_modules", "landing-2024", "landing-2024", size: 1_130 * MB, days: 290),
            build(".venv", "ml-playground", "ml-playground", size: 2_340 * MB, days: 118),
            build("Pods", "fitness-ios", "fitness-ios", size: 712 * MB, days: 45),
            build("build", "notes-android", "notes-android", size: 968 * MB, days: 34),
            build("node_modules", "admin-dashboard", "admin-dashboard", size: 845 * MB, days: 2),
            build(".dart_tool", "habit-flutter", "habit-flutter", size: 386 * MB, days: 210),
        ]
        out[.xcode] = [
            item(.xcode, "FitnessApp", path: "Library/Developer/Xcode/DerivedData/FitnessApp-bqzkxjdfuhkvtw",
                 detail: "~/Developer/fitness-ios/FitnessApp.xcodeproj", size: 6_120 * MB, days: 12),
            item(.xcode, "WeatherKitDemo", path: "Library/Developer/Xcode/DerivedData/WeatherKitDemo-akrfjwqzmxbnlp",
                 detail: "~/Developer/old/WeatherKitDemo.xcodeproj · "
                    + String(localized: "project no longer exists", comment: "Fact in a DerivedData row's detail line"),
                 size: 3_480 * MB, days: 160),
            item(.xcode, "iOS DeviceSupport · iPhone16,2 18.3 (22D63)",
                 path: "Library/Developer/Xcode/iOS DeviceSupport/iPhone16,2 18.3 (22D63)", size: 5_410 * MB, days: 200),
            item(.xcode, String(localized: "Xcode cache", comment: "Row title"), path: "Library/Caches/com.apple.dt.Xcode",
                 size: 1_860 * MB, days: 1),
            item(.xcode, String(localized: "SwiftUI previews", comment: "Row title"), path: "Library/Developer/Xcode/UserData/Previews",
                 size: 2_270 * MB, days: 9),
            item(.xcode, "FitnessApp 02-10-2026, 18.41",
                 badge: String(localized: "Newest", comment: "Badge of the newest Xcode archive of an app"),
                 path: "Library/Developer/Xcode/Archives/2026-10-02/FitnessApp.xcarchive",
                 detail: [
                    String(localized: "Version \("2.4") (\("31"))",
                           comment: "Xcode archive detail; first %@ is the app version, second %@ the build number"),
                    archiveDate(16),
                    String(localized: "uploaded to Apple", comment: "Fact in an Xcode archive's detail line"),
                    String(localized: "newest archive of this app: its build and crash symbols exist only here",
                           comment: "Fact in an Xcode archive's detail line"),
                 ].joined(separator: " · "),
                 size: 248 * MB, days: 16, safety: .risky),
            item(.xcode, "FitnessApp 14-07-2026, 11.02", path: "Library/Developer/Xcode/Archives/2026-07-14/FitnessApp.xcarchive",
                 detail: [
                    String(localized: "Version \("2.1") (\("24"))",
                           comment: "Xcode archive detail; first %@ is the app version, second %@ the build number"),
                    archiveDate(96),
                    String(localized: "uploaded to Apple", comment: "Fact in an Xcode archive's detail line"),
                    String(localized: "the build comes back from its git tag; only crash symbols for this build are lost",
                           comment: "Fact in an Xcode archive's detail line"),
                 ].joined(separator: " · "),
                 size: 231 * MB, days: 96, safety: .askAI),
        ]
        out[.simulators] = [
            item(.simulators, String(localized: "\("iOS 17.5") runtime", comment: "Simulator runtime row title; %@ is a platform like iOS 17.5"),
                 badge: String(localized: "Runtime", comment: "Badge of a simulator runtime"),
                 path: "/Library/Developer/CoreSimulator/Volumes/iOS_21F79",
                 detail: String(localized: "Build \("21F79")", comment: "Simulator runtime detail; %@ is a build number like 21F79")
                    + " · " + used(150) + " · "
                    + String(localized: """
                        \(3) devices stop working without it; getting it back is a \((7_340 * MB).formattedBytes) download
                        """, comment: "Fact in a simulator runtime's detail line; %lld is the number of devices, %@ a download size"),
                 size: 7_340 * MB, days: 150, removal: .simulatorRuntime(id: "demo-17-5")),
            item(.simulators, "iPhone 15 Pro", badge: String(localized: "Device", comment: "Badge of a simulator device"),
                 path: "Library/Developer/CoreSimulator/Devices/1",
                 detail: "iOS 17.5 · " + used(150) + " · " + keeps("iOS 17.5"), size: 3_120 * MB, days: 150,
                 removal: .simulatorDevice(udid: "demo-1")),
            item(.simulators, "iPad Air 11-inch", badge: String(localized: "Device", comment: "Badge of a simulator device"),
                 path: "Library/Developer/CoreSimulator/Devices/2",
                 detail: "iOS 18.2 · " + used(60) + " · " + keeps("iOS 18.2"), size: 1_870 * MB, days: 60,
                 removal: .simulatorDevice(udid: "demo-2")),
            item(.simulators, "iPhone 14",
                 badge: String(localized: "Unavailable", comment: "Badge of a simulator device whose iOS version is gone"), path: "Library/Developer/CoreSimulator/Devices/3",
                 detail: "iOS 16.4 · " + cantRun(),
                 size: 1_240 * MB, days: 400, safety: .safe, removal: .simulatorDevice(udid: "demo-3")),
            item(.simulators, "iPhone 17", badge: String(localized: "Device", comment: "Badge of a simulator device"),
                 path: "Library/Developer/CoreSimulator/Devices/4",
                 detail: "iOS 26.1 · " + used(0.1) + " · " + keeps("iOS 26.1"), size: 2_650 * MB, days: 0.1,
                 removal: .simulatorDevice(udid: "demo-4"),
                 locked: String(localized: "Running. Shut it down to remove it.", comment: "Why a running simulator device can't be selected")),
        ]
        out[.android] = [
            item(.android, "NDK 25.1.8937393", path: "Library/Android/sdk/ndk/25.1.8937393",
                 detail: String(localized: "Android NDK version; projects that pin it download it again", comment: "Row detail"),
                 size: 2_200 * MB, days: 300),
            item(.android, "NDK 26.1.10909125", path: "Library/Android/sdk/ndk/26.1.10909125",
                 detail: String(localized: "Android NDK version; projects that pin it download it again", comment: "Row detail"),
                 size: 3_110 * MB, days: 180),
            item(.android, String(localized: "Gradle caches", comment: "Row title"), path: ".gradle/caches", size: 4_650 * MB, days: 3),
            item(.android, "Android 34 · google apis · arm64-v8a", path: "Library/Android/sdk/system-images/android-34/google_apis/arm64-v8a",
                 detail: String(localized: "Android SDK system image", comment: "Row detail"), size: 2_130 * MB, days: 220),
            item(.android, "Pixel 7 API 34", badge: String(localized: "Emulator", comment: "Badge of an Android emulator (AVD) row"), path: ".android/avd/Pixel_7_API_34.avd",
                 detail: String(localized: "Android emulator with its apps and data", comment: "Detail of an Android emulator row")
                    + " · " + changed(210),
                 size: 6_480 * MB, days: 210),
        ]
        out[.packageCaches] = [
            item(.packageCaches, String(localized: "npm cache", comment: "Row title"), path: ".npm/_cacache",
                 size: 3_210 * MB, days: 2),
            item(.packageCaches, String(localized: "Homebrew downloads", comment: "Row title"), path: "Library/Caches/Homebrew",
                 size: 1_480 * MB, days: 6),
            item(.packageCaches, String(localized: "Yarn cache", comment: "Row title"), path: "Library/Caches/Yarn",
                 size: 920 * MB, days: 40),
            item(.packageCaches, String(localized: "pip cache", comment: "Row title"), path: "Library/Caches/pip",
                 size: 610 * MB, days: 25),
            item(.packageCaches, String(localized: "CocoaPods cache", comment: "Row title"), path: "Library/Caches/CocoaPods",
                 size: 430 * MB, days: 45),
        ]
        out[.docker] = [
            item(.docker, String(localized: "Build cache", comment: "Title of Docker's build cache row"),
                 badge: String(localized: "Cache", comment: "Badge of Docker's build cache row"), path: "/var/lib/docker/buildkit",
                 detail: String(localized: "Layers kept by docker build; the next build takes longer",
                                comment: "Detail of Docker's build cache row; docker build is a command"),
                 size: 7_920 * MB, removal: .docker(.buildCache)),
            item(.docker, "postgres:15", badge: String(localized: "Image", comment: "Badge of a Docker image"), path: "/docker/postgres",
                 detail: String(localized: "Created \(ago(days: 120).relativeDescription)",
                                comment: "Docker image detail; %@ is the image's age like '3 months ago'"),
                 size: 412 * MB, days: 120, removal: .docker(.image("demo-pg", stoppedContainers: []))),
            item(.docker, "node:20-alpine", badge: String(localized: "Image", comment: "Badge of a Docker image"), path: "/docker/node",
                 detail: String(localized: "Created \(ago(days: 60).relativeDescription)",
                                comment: "Docker image detail; %@ is the image's age like '3 months ago'")
                    + " · " + String(localized: "also removes stopped containers \("shop-web-app-1, shop-web-worker-1")",
                                     comment: "Docker image detail; %@ is a comma-separated list of container names"),
                 size: 1_340 * MB, days: 60, removal: .docker(.image("demo-node", stoppedContainers: ["a", "b"]))),
            // Docker reports a container's status in English; the app shows it as is.
            item(.docker, "shop-web-db-1", badge: String(localized: "Container", comment: "Badge of a stopped Docker container"),
                 path: "/docker/c1", detail: "postgres:15 · Exited (0) 5 weeks ago",
                 size: 86 * MB, days: 35, removal: .docker(.container("demo-c1"))),
        ]
        out[.aiModels] = [
            item(.aiModels, "Ollama · llama3.1:8b", path: ".ollama/models/llama3.1-8b", size: 4_920 * MB, days: 75),
            item(.aiModels, "Ollama · qwen2.5-coder:7b", path: ".ollama/models/qwen2.5-coder-7b", size: 4_680 * MB, days: 30),
            item(.aiModels, "Hugging Face · openai/whisper-large-v3", path: ".cache/huggingface/hub/models--openai--whisper-large-v3",
                 size: 3_090 * MB, days: 140),
        ]
        out[.aiAgents] = [
            item(.aiAgents, String(localized: "Claude Code sessions · \("~/Developer/shop-web")",
                                   comment: "AI Agents row title; %@ is a project path like ~/www/app"),
                 badge: "Claude", path: ".claude/projects/-Users-demo-Developer-shop-web",
                 detail: String(localized: "Session history /resume uses",
                                comment: "AI Agents row note; /resume is Claude Code's command, keep it as is") + " · " + lastChanged(21),
                 size: 1_430 * MB, days: 21, safety: .askAI),
            item(.aiAgents, String(localized: "Codex sessions · \("2026")-\("08")",
                                   comment: "AI Agents row title; first %@ is a year, second %@ a month number, e.g. 2026-08"),
                 badge: "Codex", path: ".codex/sessions/2026/08",
                 detail: String(localized: "Session history `codex resume` uses",
                                comment: "AI Agents row note; `codex resume` is a command, keep it as is") + " · " + lastChanged(45),
                 size: 2_120 * MB, days: 45, safety: .askAI),
            item(.aiAgents, String(localized: "Cursor state backup", comment: "AI Agents row title"), badge: "Cursor",
                 path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb.backup",
                 detail: String(localized: "One-time backup of Cursor's state database (chat history lives in the live copy)",
                                comment: "AI Agents row note for Cursor's state backup") + " · " + lastChanged(60),
                 size: 890 * MB, days: 60, safety: .askAI),
            item(.aiAgents, String(localized: "\("Cursor") old extension versions (\(12))",
                                   comment: "AI Agents row title; %@ is an editor (Cursor, VS Code…), %lld the number of versions"),
                 badge: "Cursor", path: ".cursor/extensions",
                 detail: String(localized: "Older copies kept after extensions updated",
                                comment: "AI Agents row note for an editor's old extension versions") + " · " + lastChanged(50),
                 size: 640 * MB, days: 50, safety: .safe),
            item(.aiAgents, String(localized: "Gemini CLI temporary files", comment: "AI Agents row title"), badge: "Antigravity",
                 path: ".gemini/tmp",
                 detail: AgentsScanner.historyNote + " · " + lastChanged(12),
                 size: 320 * MB, days: 12, safety: .askAI),
        ]
        out[.apps] = [
            item(.apps, "Photo Editor Pro", path: "/Applications/Photo Editor Pro.app",
                 detail: appDetail(1_400 * MB, 2_100 * MB, places: 5, days: 240), size: 3_500 * MB, days: 240),
            item(.apps, "Video Converter", path: "/Applications/Video Converter.app",
                 detail: appDetail(620 * MB, 340 * MB, places: 3, days: 400), size: 960 * MB, days: 400),
            item(.apps, "Old Game", path: "/Applications/Old Game.app",
                 detail: appDetail(2_800 * MB, 410 * MB, places: 4, days: 420), size: 3_210 * MB, days: 420),
        ]
        out[.leftovers] = [
            item(.leftovers, "com.example.musicplayer", path: "Library/Application Support/com.example.musicplayer",
                 detail: leftoverDetail("com.example.musicplayer", days: 200), size: 540 * MB, days: 200),
            item(.leftovers, "com.example.vpnclient", path: "Library/Application Support/com.example.vpnclient",
                 detail: leftoverDetail("com.example.vpnclient", days: 150), size: 120 * MB, days: 150),
        ]
        out[.appCaches] = [
            item(.appCaches, "Music streaming app", path: "Library/Caches/com.example.music", size: 2_310 * MB, days: 1),
            item(.appCaches, "Team chat", path: "Library/Caches/com.example.chat", size: 1_120 * MB, days: 1),
            item(.appCaches, "Video editor", path: "Library/Caches/com.example.videoeditor", size: 940 * MB, days: 2),
        ]
        out[.browserCaches] = [
            // Browser rows are titled with the browser's name, as BrowserCachesScanner shows them.
            item(.browserCaches, "Google Chrome", path: "Library/Caches/Google/Chrome", size: 1_830 * MB, days: 1),
            item(.browserCaches, "Firefox", path: "Library/Caches/Firefox", size: 760 * MB, days: 9),
        ]
        out[.logs] = [item(.logs, String(localized: "Logs", comment: "Category: diagnostic logs and crash reports"),
                           path: "Library/Logs", size: 412 * MB, days: 1)]
        out[.installers] = [
            item(.installers, "Docker.dmg", path: "Downloads/Docker.dmg", size: 610 * MB, days: 95),
            item(.installers, "Xcode_16.2.xip", path: "Downloads/Xcode_16.2.xip", size: 3_050 * MB, days: 230),
        ]
        out[.oldDownloads] = [
            item(.oldDownloads, "conference-talk.mov", path: "Downloads/conference-talk.mov", size: 2_430 * MB, days: 180),
            item(.oldDownloads, "dataset-2025.zip", path: "Downloads/dataset-2025.zip", size: 1_210 * MB, days: 300),
        ]
        out[.temporary] = [
            item(.temporary, "build-cache-x8f2",
                 badge: String(localized: "System temp", comment: "Badge of an item in the system's temporary folders"),
                 path: "/private/tmp/build-cache-x8f2", size: 640 * MB, days: 6),
        ]
        out[.largeFiles] = [
            item(.largeFiles, "screen-recording-final.mov", path: "Movies/screen-recording-final.mov", size: 6_820 * MB, days: 150),
            item(.largeFiles, "ubuntu-24.04-arm64.iso", path: "VMs/ubuntu-24.04-arm64.iso", size: 3_010 * MB, days: 260),
        ]
        out[.duplicates] = [
            ("Movies/family-trip-2026.mp4", 1_240 * MB, 60.0, true), ("Desktop/family-trip-2026.mp4", 1_240 * MB, 40.0, false),
            ("Documents/Contract-signed.pdf", 4 * MB, 120.0, true), ("Downloads/Contract-signed.pdf", 4 * MB, 90.0, false),
            ("Downloads/Contract-signed (1).pdf", 4 * MB, 30.0, false),
        ].map { path, size, days, oldest in
            let full = home + "/" + path
            let group = home + "/" + (path.hasSuffix(".mp4") ? "Movies/family-trip-2026.mp4" : "Documents/Contract-signed.pdf")
            var copy = item(.duplicates, PathDisplay.abbreviated(full),
                            badge: oldest ? String(localized: "Oldest copy", comment: "Badge of the oldest copy among duplicates") : nil,
                            path: path,
                            detail: String(localized: "created \(ago(days: days).relativeDescription)",
                                           comment: "Fact in a Duplicates row's detail line; %@ is a relative date like '3 months ago'"),
                            size: size, days: days)
            copy.duplicateGroup = group
            copy.isOldestCopy = oldest
            return copy
        }
        out[.devices] = [
            // A backup is titled with the device's name.
            item(.devices, "iPhone 13", badge: String(localized: "Backup", comment: "Badge of an iPhone or iPad backup"), path: "Library/Application Support/MobileSync/Backup/demo",
                 detail: "iOS 17.6 · " + String(localized: "backed up \(ago(days: 380).formatted(date: .abbreviated, time: .omitted))",
                                               comment: "Fact in a device backup's detail line; %@ is a date"),
                 size: 48_200 * MB, days: 380),
        ]
        out[.trash] = [CleanupItem(id: "trash", category: .trash, title: String(localized: "Trash", comment: "Category: the macOS Trash"),
                                   detail: String(localized: "\(1_284) files", comment: "Detail of the Trash row; %lld is the number of files"),
                                   size: 2_640 * MB, removal: .emptyTrash)]
        var results: [CategoryID: CategoryResult] = [:]
        for category in CategoryID.allCases {
            let items = (out[category] ?? []).sorted { $0.size > $1.size }
            results[category] = CategoryResult(state: .done, items: items)
        }
        results[.simulators]?.items.sort { $0.size > $1.size }
        return results
    }

    static func disk() -> DiskSpace { DiskSpace(total: 994_660 * MB, available: 412_380 * MB) }

    static func storage() -> StorageReport {
        var report = StorageReport()
        report.totals = [
            .apps: 58_400 * MB, .developer: 96_200 * MB, .photos: 41_300 * MB, .videos: 37_800 * MB,
            .music: 6_200 * MB, .documents: 12_900 * MB, .archives: 18_600 * MB, .deviceBackups: 48_200 * MB,
            .mail: 9_800 * MB, .appData: 71_500 * MB, .trash: 2_640 * MB, .other: 34_700 * MB,
        ]
        report.diskUsed = 582_280 * MB
        func folder(_ path: String, _ bytes: Int64, _ count: Int, sub: [(String, Int64, Int)] = []) -> StorageReport.FolderUsage {
            var usage = StorageReport.FolderUsage(path: home + "/" + path, bytes: bytes, files: [], fileCount: count)
            for (name, size, files) in sub {
                usage.subfolders[home + "/" + path + "/" + name] = StorageReport.SubfolderUsage(bytes: size, fileCount: files)
            }
            return usage
        }
        report.folders = [
            .photos: [
                folder("Pictures/Photos Library.photoslibrary", 29_800 * MB, 18_420),
                folder("Pictures/Trips", 6_900 * MB, 2_310, sub: [("2025 Japan", 3_400 * MB, 1_120), ("2026 Alps", 2_100 * MB, 760)]),
                folder("Desktop/Screenshots", 2_100 * MB, 1_840),
            ],
            .developer: [
                folder("Library/Developer", 41_200 * MB, 210_000),
                folder("Developer/shop-web", 4_300 * MB, 96_000),
                folder(".gradle", 6_800 * MB, 54_000),
            ],
        ]
        let more: [StorageBucket: [(String, Double, Int)]] = [
            .appData: [("Library/Application Support", 0.55, 41_000), ("Library/Caches", 0.3, 88_000), ("Library/Containers", 0.15, 23_000)],
            .apps: [("/Applications/Xcode.app", 0.48, 1), ("/Applications/Photo Editor Pro.app", 0.12, 1), ("/Applications/Old Game.app", 0.1, 1)],
            .deviceBackups: [("Library/Application Support/MobileSync", 1, 2)],
            .videos: [("Movies", 0.62, 140), ("Downloads", 0.24, 18), ("Desktop", 0.14, 9)],
            .other: [("Developer", 0.4, 52_000), ("Downloads", 0.25, 830), ("Documents", 0.2, 4_100)],
            .archives: [("Downloads", 0.58, 64), ("VMs", 0.32, 3), ("Documents", 0.1, 41)],
            .documents: [("Documents", 0.66, 3_900), ("Desktop", 0.2, 610), ("Downloads", 0.14, 420)],
            .mail: [("Library/Mail", 0.82, 96_000), ("Library/Messages", 0.18, 12_000)],
            .music: [("Music", 0.9, 2_300), ("Downloads", 0.1, 60)],
            .trash: [(".Trash", 1, 1_284)],
        ]
        for (bucket, list) in more {
            let total = Double(report.totals[bucket] ?? 0)
            report.folders[bucket] = list.map { name, share, count in
                StorageReport.FolderUsage(path: name.hasPrefix("/") ? name : home + "/" + name, bytes: Int64(total * share),
                                          files: [], fileCount: count)
            }
        }
        return report
    }

    static func stats() -> StatsStore.Stats {
        var stats = StatsStore.Stats()
        stats.firstUse = ago(days: 47)
        stats.cleanedBytes = 214_600 * MB
        stats.cleanups = 38
        stats.itemsRemoved = 1_203
        let sizes = results().mapValues(\.totalSize)
        stats.lastScan = StatsStore.ScanSummary(date: ago(days: 0.02), seconds: 21, found: sizes.values.reduce(0, +),
                                                categorySizes: Dictionary(uniqueKeysWithValues: sizes.map { ($0.key.rawValue, $0.value) }))
        let report = storage()
        stats.lastStorage = StatsStore.StorageSummary(
            date: ago(days: 0.02),
            totals: Dictionary(uniqueKeysWithValues: report.totals.map { ($0.key.rawValue, $0.value) }),
            notMeasured: report.notMeasured
        )
        stats.history = [
            .init(date: ago(days: 0.3), movedToTrash: 12_400 * MB, removedByTools: 7_340 * MB, items: 14),
            .init(date: ago(days: 3), movedToTrash: 8_920 * MB, removedByTools: 0, items: 6),
            .init(date: ago(days: 9), movedToTrash: 21_300 * MB, removedByTools: 3_100 * MB, items: 31),
            .init(date: ago(days: 16), movedToTrash: 4_210 * MB, removedByTools: 0, items: 3),
        ]
        return stats
    }
}

extension FileTarget {
    /// A path that doesn't exist on this Mac (device and inode 0, so `Remover` refuses it).
    init(demoPath: String) {
        path = demoPath
        device = 0
        inode = 0
    }
}
#endif
