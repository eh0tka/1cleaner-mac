import Foundation

/// Known tool locations, relative to the home folder. Adding a cache = one line here.
/// Never list source, credentials, signing material or tool settings.
enum KnownLocations {
    static let xcode: [Location] = [
        Location("Library/Developer/Xcode/DerivedData", naming: .derivedData, perChild: true),
        Location("Library/Developer/Xcode/*DeviceSupport", naming: .parentAndName, perChild: true),
        Location("Library/Caches/com.apple.dt.Xcode", naming: .fixed(String(localized: "Xcode cache", comment: "Row title"))),
        Location("Library/Developer/Xcode/UserData/Previews",
                 naming: .fixed(String(localized: "SwiftUI previews", comment: "Row title"))),
        Location("Library/Developer/CoreSimulator/Caches",
                 naming: .fixed(String(localized: "Simulator caches", comment: "Row title"))),
        Location("Library/Developer/XCTestDevices",
                 naming: .fixed(String(localized: "Test simulator clones", comment: "Row title: simulators copied for UI tests"))),
        Location("Library/Developer/DVTDownloads", naming: .fixed(String(localized: "Xcode downloads", comment: "Row title"))),
        Location("Library/Developer/Xcode/Archives/*", naming: .archive, perChild: true),
        Location("Library/Developer/Xcode/iOS Device Logs",
                 naming: .fixed(String(localized: "Device logs", comment: "Row title: logs copied from iPhones and iPads"))),
    ]

    static let android: [Location] = [
        Location(".gradle/caches", naming: .fixed(String(localized: "Gradle caches", comment: "Row title"))),
        Location(".gradle/wrapper/dists",
                 naming: .name(prefix: String(localized: "Gradle wrapper", comment: "Row title, followed by a version folder name") + " · "),
                 perChild: true),
        Location(".gradle/daemon", naming: .fixed(String(localized: "Gradle daemon logs", comment: "Row title"))),
        Location(".android/cache", naming: .fixed(String(localized: "Android cache", comment: "Row title"))),
        Location(".android/build-cache", naming: .fixed(String(localized: "Android build cache", comment: "Row title"))),
        Location("Library/Caches/Google/AndroidStudio*",
                 naming: .name(prefix: String(localized: "Android Studio cache",
                                              comment: "Row title, followed by a version folder name") + " · ")),
        Location("Library/Android/sdk/system-images/*/*/*", naming: .systemImage,
                 detail: String(localized: "Android SDK system image", comment: "Row detail")),
        Location("Library/Android/sdk/ndk", naming: .name(prefix: "NDK "), perChild: true,
                 detail: String(localized: "Android NDK version; projects that pin it download it again", comment: "Row detail")),
        Location("Library/Android/sdk/build-tools",
                 naming: .name(prefix: String(localized: "Build tools", comment: "Android row title, followed by a version number") + " "),
                 perChild: true, detail: String(localized: "Android SDK build tools version", comment: "Row detail")),
        Location("Library/Android/sdk/platforms",
                 naming: .name(prefix: String(localized: "SDK platform",
                                              comment: "Android row title, followed by a platform folder name") + " "),
                 perChild: true, detail: String(localized: "Android SDK platform", comment: "Row detail")),
        Location(".gradle/jdks", naming: .name(prefix: "Gradle JDK · "), perChild: true,
                 detail: String(localized: "Java downloaded by Gradle toolchains", comment: "Row detail")),
    ]

    static let packageCaches: [Location] = [
        Location(".npm/_cacache", naming: .fixed(String(localized: "npm cache", comment: "Row title"))),
        Location("Library/Caches/Yarn", naming: .fixed(String(localized: "Yarn cache", comment: "Row title"))),
        Location(".yarn/berry/cache", naming: .fixed(String(localized: "Yarn Berry cache", comment: "Row title"))),
        Location("Library/pnpm/store", naming: .fixed(String(localized: "pnpm store", comment: "Row title")),
                 detail: String(localized: "Projects link their packages from here", comment: "Row detail")),
        Location(".bun/install/cache", naming: .fixed(String(localized: "Bun cache", comment: "Row title"))),
        Location("Library/Caches/Homebrew", naming: .fixed(String(localized: "Homebrew downloads", comment: "Row title"))),
        Location("Library/Caches/pip", naming: .fixed(String(localized: "pip cache", comment: "Row title"))),
        Location(".cache/uv", naming: .fixed(String(localized: "uv cache", comment: "Row title"))),
        Location("Library/Caches/CocoaPods", naming: .fixed(String(localized: "CocoaPods cache", comment: "Row title"))),
        Location("Library/Caches/org.swift.swiftpm", naming: .fixed(String(localized: "Swift Package Manager cache", comment: "Row title"))),
        Location("Library/Caches/org.carthage.CarthageKit", naming: .fixed(String(localized: "Carthage cache", comment: "Row title"))),
        Location("Library/Caches/go-build", naming: .fixed(String(localized: "Go build cache", comment: "Row title"))),
        Location(".cargo/registry/cache", naming: .fixed(String(localized: "Cargo downloads", comment: "Row title"))),
        Location(".cargo/registry/index", naming: .fixed(String(localized: "Cargo registry index", comment: "Row title"))),
        Location(".cargo/git/db", ".cargo/git/checkouts",
                 naming: .fixed(String(localized: "Cargo git dependencies", comment: "Row title")),
                 detail: "~/.cargo/git"),
        // Go keeps its modules read-only; Remover makes them writable first so the Trash can be emptied.
        Location("go/pkg/mod", naming: .fixed(String(localized: "Go modules", comment: "Row title")),
                 detail: String(localized: "Projects download them again on the next build", comment: "Row detail")),
        Location(".pub-cache/hosted", naming: .fixed(String(localized: "Dart and Flutter packages", comment: "Row title")),
                 detail: String(localized: "`flutter pub get` downloads them again", comment: "Row detail")),
        Location(".nuget/packages", naming: .fixed(String(localized: "NuGet packages", comment: "Row title"))),
        Location(".local/share/NuGet/http-cache", naming: .fixed(String(localized: "NuGet HTTP cache", comment: "Row title"))),
        Location("Library/Caches/pypoetry", naming: .fixed(String(localized: "Poetry cache", comment: "Row title")),
                 detail: String(localized: "Includes Poetry's virtual environments; `poetry install` creates them again",
                                comment: "Row detail")),
        Location("Library/Caches/node-gyp", naming: .fixed(String(localized: "node-gyp headers", comment: "Row title"))),
        Location("Library/Caches/electron", naming: .fixed(String(localized: "Electron downloads", comment: "Row title"))),
        Location("Library/Caches/electron-builder", naming: .fixed(String(localized: "electron-builder cache", comment: "Row title"))),
        Location("Library/Caches/deno", naming: .fixed(String(localized: "Deno cache", comment: "Row title"))),
        Location("Library/Caches/typescript", naming: .fixed(String(localized: "TypeScript cache", comment: "Row title"))),
        Location("Library/Caches/composer", naming: .fixed(String(localized: "Composer cache", comment: "Row title"))),
        Location(".cache/prisma", naming: .fixed(String(localized: "Prisma engines", comment: "Row title"))),
        Location("Library/Caches/ms-playwright", naming: .fixed(String(localized: "Playwright browsers", comment: "Row title")),
                 detail: String(localized: "Tests need `npx playwright install` afterwards", comment: "Row detail")),
        Location(".cache/puppeteer", naming: .fixed(String(localized: "Puppeteer browsers", comment: "Row title"))),
        Location(".m2/repository", naming: .fixed(String(localized: "Maven repository", comment: "Row title")),
                 detail: String(localized: "May hold artifacts you installed locally", comment: "Row detail")),
    ]

    static let aiModels: [Location] = [
        Location(".ollama/models", naming: .fixed(String(localized: "Ollama models", comment: "Row title")),
                 detail: String(localized: "All models pulled with Ollama; `ollama pull` downloads them again", comment: "Row detail")),
        Location(".lmstudio/models/*", naming: .parentAndName, perChild: true),
        Location(".cache/lm-studio/models/*", naming: .parentAndName, perChild: true),
        Location(".cache/huggingface/hub", naming: .huggingFace, perChild: true),
    ]

    static let devices: [Location] = [
        Location("Library/iTunes/iPhone Software Updates", naming: .name(prefix: ""), perChild: true,
                 detail: String(localized: "Downloaded iPhone update; Finder downloads it again when needed", comment: "Row detail")),
        Location("Library/iTunes/iPad Software Updates", naming: .name(prefix: ""), perChild: true,
                 detail: String(localized: "Downloaded iPad update; Finder downloads it again when needed", comment: "Row detail")),
    ]

    static let editors: [Location] = [
        editorCaches(app: "Code", title: String(localized: "VS Code caches", comment: "Row title")),
        editorCaches(app: "Cursor", title: String(localized: "Cursor caches", comment: "Row title")),
        editorCaches(app: "Windsurf", title: String(localized: "Windsurf caches", comment: "Row title")),
        Location("Library/Caches/JetBrains/*",
                 naming: .name(prefix: String(localized: "JetBrains cache", comment: "Row title, followed by a product folder name") + " · ")),
        Location("Library/Caches/Zed", naming: .fixed(String(localized: "Zed cache", comment: "Row title"))),
    ]

    /// Browser names, not localized: `BrowserCachesScanner.bundleIDs` looks the row titles up.
    static let browsers: [Location] = [
        Location("Library/Caches/com.apple.Safari", naming: .fixed("Safari")),
        Location("Library/Caches/Google/Chrome", naming: .fixed("Google Chrome")),
        Location("Library/Caches/Google/Chrome Canary", naming: .fixed("Chrome Canary")),
        Location("Library/Caches/Chromium", naming: .fixed("Chromium")),
        Location("Library/Caches/Microsoft Edge", naming: .fixed("Microsoft Edge")),
        Location("Library/Caches/BraveSoftware/Brave-Browser", naming: .fixed("Brave")),
        Location("Library/Caches/Arc", naming: .fixed("Arc")),
        Location("Library/Caches/company.thebrowser.Browser", naming: .fixed("Arc")),
        Location("Library/Caches/Firefox", naming: .fixed("Firefox")),
        Location("Library/Caches/com.operasoftware.Opera", naming: .fixed("Opera")),
        Location("Library/Caches/Vivaldi", naming: .fixed("Vivaldi")),
        Location("Library/Caches/Yandex/YandexBrowser", naming: .fixed("Yandex Browser")),
    ]

    private static func editorCaches(app: String, title: String) -> Location {
        let base = "Library/Application Support/\(app)/"
        return Location(
            base + "Cache", base + "CachedData", base + "CachedExtensionVSIXs", base + "Code Cache", base + "GPUCache",
            naming: .fixed(title),
            detail: "~/" + base.dropLast()
        )
    }

    /// iCloud and file-sync service data, never shown or touched: removing it can break files
    /// in iCloud Drive and other synced folders, which PureMac learned from a user report (issue #142).
    static let syncServiceFolders = [
        "Library/Caches/CloudKit", "Library/Caches/com.apple.bird", "Library/Caches/com.apple.cloudd",
        "Library/Caches/com.apple.cloudkit", "Library/Caches/com.apple.FileProvider",
        "Library/Application Support/CloudDocs", "Library/Application Support/FileProvider",
        "Library/Mobile Documents", "Library/CloudStorage", "Library/Daemon Containers",
    ]

    /// True for a path in or under `syncServiceFolders`, or in a container of the iCloud and file-provider
    /// services themselves (`com.apple.CloudDocs.*`, `*.FileProvider*`).
    static func isSyncServiceData(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        if syncServiceFolders.contains(where: { path == home + "/" + $0 || path.hasPrefix(home + "/" + $0 + "/") }) {
            return true
        }
        // Inside ~/Library only: a project called cloudkit-notes is the person's own.
        let lower = path.lowercased()
        guard lower.hasPrefix((home + "/Library/").lowercased()) else { return false }
        return ["clouddocs", "fileprovider", "cloudkit", "com.apple.bird", "com.apple.cloudd"].contains {
            lower.contains($0)
        }
    }

    /// Folders older sync apps keep right in the home folder (today they live in ~/Library/CloudStorage): a file
    /// removed there is removed from the cloud too, also for everyone a folder is shared with, so their files are
    /// never offered as large files or duplicates.
    static func isInSyncedHomeFolder(_ path: String, home: String) -> Bool {
        guard path.hasPrefix(home + "/") else { return false }
        let first = path.dropFirst(home.count + 1).split(separator: "/").first.map(String.init) ?? ""
        return ["Google Drive", "My Drive", "Box", "Box Sync", "MEGA", "pCloud Drive", "Yandex.Disk", "Yandex.Disk.localized",
                "Nextcloud", "ownCloud", "Sync", "Creative Cloud Files"].contains(first)
            || first.hasPrefix("Dropbox") || first.hasPrefix("OneDrive")
    }

    /// Top-level `~/Library/Caches` folders shown by a specific category, left out of App Caches.
    static let claimedCacheFolders: Set<String> = {
        let all = xcode + android + packageCaches + editors + browsers
        var names = Set<String>()
        for location in all {
            for path in location.paths where path.hasPrefix("Library/Caches/") {
                if let first = path.dropFirst("Library/Caches/".count).split(separator: "/").first {
                    names.insert(String(first))
                }
            }
        }
        return names
    }()
}
