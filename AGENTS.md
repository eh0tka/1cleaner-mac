# 1Cleaner for Mac — guide for contributors and coding agents

Read `docs/PRODUCT.md` (the product contract) first. The rules below protect people's files and keep the product
behavior stable: don't change them without the maintainer's explicit approval.

## Product rules

- Developer ID direct download, **no App Sandbox**. The site version is free with optional crypto
  support: the toolbar heart, and the Support sheet once, after the first cleanup that freed space (never
  again after that). Addresses live only in `Core/Donations.swift` and onebuckapps.com/donate/; only the maintainer changes
  them. Updates are checked only when the person asks (About, app menu), never in the background. *Install and
  Relaunch* (`Services/Updater.swift`), only on a click: downloads the DMG `version.json` names
  (`dmg`, `sha256`), checks the hash, the bundle id, a higher build and a Developer ID signature of the same team as
  the running copy, puts the new app in its place (the old one goes to the Trash) and restarts. Whatever it can't do
  safely leaves the copy as it is and offers the website's Download.
- Every file-based removal goes to the **Trash** (`FileManager.trashItem`) after the confirmation sheet. Never
  `removeItem` on scanned files.
- Docker (`docker rm`, `docker rmi`, `docker volume rm`, `docker builder prune --all --force`) and simulators (`xcrun simctl delete`,
  `xcrun simctl runtime delete`) are removed by their tools after a separate red "can't be undone" confirmation.
  Only volumes no container uses are listed, with a red warning; images of running
  containers and attached volumes never. An image used by stopped containers removes them with it. The app
  never starts Docker or stops
  running simulators/tools.
- Result screen: moved to Trash, removed by tools, failures with reasons, free space before → after, and
  **Empty Trash…** (own confirmation; Finder empties the whole Trash).
- **iCloud and file-sync service data is never touched**: `KnownLocations.syncServiceFolders`
  and `isSyncServiceData`; `AppModel` drops any result that touches them.
- **Nothing is preselected**: after a scan every item is unchecked; the person selects by
  hand (per item or Select All per category). Never reintroduce automatic selection without the maintainer.
  Leaving a screen with checked items asks Clean / Clear Selection / Cancel; never clear or
  carry a selection silently.
- Trash moves stay inside the home folder; the only exceptions are app bundles in /Applications (uninstaller,
  other Xcode copies) and items in /private/tmp and this user's macOS temp folder (`TemporaryScanner.systemRoots`). The uninstaller matches leftovers by bundle id only (no partial names).
- Move to Another Disk (`Mover`): copy with ditto → verify files and length → only then the original to the Trash;
  on failure remove only the mover's own partial copy.
- A build folder is offered only next to the file that proves its tool (`node_modules` + `package.json`, ...).
  Never offer source, lockfiles, `.git`, credentials, signing keys or tool settings.
- Safe List (items + folders, `SettingsStore`) is applied to every scan result; Select All touches only the
  rows the list shows (size filter + search). Usage stats (`StatsStore`) stay in UserDefaults on this Mac.
- Safety labels (Safe / Ask AI / Risky) come only from the table in `Core/Safety.swift`; new categories must be
  added there, and changing a level needs the maintainer. AI Agents rows carry their level from `AgentsScanner`. Labels are hints and never select anything.
- No network, analytics, account or third-party dependencies. Light appearance, 1Buck brand (see `Core/Theme.swift`).

## Localization

- 17 languages; every user-facing text is a SwiftUI literal or `String(localized:comment:)`,
  one whole sentence per key, counts as `Int` interpolations. Never decide logic by displayed text (badges are
  translated: use paths, `removal` or `safetyLevel`). New or changed strings ship translated and independently
  reviewed in all languages: follow `tools/l10n/README.md`.

## Architecture

- `OneCleanerMac/App` — `@main` app, `AppModel` (scan, selection, Safe List, cleanup, Trash, stats), `DebugLaunch`.
- `OneCleanerMac/Core` — models (`CategoryID`, `CleanupItem`, `Removal`), theme, formatting.
- `OneCleanerMac/Scanners` — one `Scanner` per area, run in parallel. Known tool paths are data in
  `KnownLocations.swift` (adding a cache = one line). `ProjectScanner` walks the scan folders once for build
  folders, large files and duplicates.
- `Services/StorageAnalyzer.swift` — the read-only storage breakdown (kind → folders → largest files); it is
  separate from the cleanup scanners and never offers anything for removal.
- `OneCleanerMac/Services` — `FileSizer` (`fts`, no symlink follow, one volume, hard links once), `ProcessRunner`
  (absolute path, no shell, timeout), `Remover` (re-checks path, inode, symlinks before the Trash), system access.
- `OneCleanerMac/Features` — SwiftUI screens. The Xcode project uses synchronized folders: new files compile
  automatically. `tools/render_app_icon.swift` renders the macOS icon from the iPhone icon.
- Blocking file-system and tool work never runs on the main actor; scans and cleanup are cancellable.

## Commands

- Build: `xcodebuild -project OneCleanerMac.xcodeproj -scheme OneCleanerMac -configuration Debug build` (add
  `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` without the maintainer's signing team).
- Headless QA (DEBUG, read-only): launch with `-autoScan YES -snapshotDir <dir>`; the app scans, writes a PNG
  per screen plus `summary.txt`, then quits (without `-autoScan`, it captures the screens as they open).
  `-openCategory <id>` opens a category, `-rescanCategory <id>` rescans one, `-openSupport YES` opens the Support
  sheet, `-expandDuplicates YES` opens every duplicate set, `-hideSidebar YES` hides the sidebar (snapshots of a
  locked screen can't draw it), `-debugMoveSource <path> -debugMoveTo <folder> -snapshotDir <dir>` runs one Move
  (test data only). Never press Clean on a real Mac in an automated run.
- Screenshots for publishing: `-demoData YES -snapshotDir <dir>` fills every screen with made-up data
  (`App/DemoData.swift`, separate defaults suite, nothing can be cleaned). From a real Mac only screens with totals
  (the Dashboard) may be published; screens with project, app or account names always use demo data.
  `-checkForUpdates YES -snapshotDir <dir>` checks the live
  `version.json` and writes `update.png`; build with `CURRENT_PROJECT_VERSION=0` to see "is available".
- Release DMG: `SIGNING_IDENTITY=… TEAM_ID=… tools/release.sh` → `build/dist/1Cleaner-<version>-<build>.dmg`:
  universal, signed with Developer ID, notarized, stapled and checked with `spctl` (`--no-notarize` builds and
  signs without sending anything).
  Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Configuration/Base.xcconfig` first and add the
  version to `RELEASE_NOTES.md`. The maintainer publishes the DMG on onebuckapps.com and updates its
  `version.json` (with the DMG's `dmg` URL and `sha256`), which Check for Updates and Install and Relaunch read.
