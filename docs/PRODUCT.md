# 1Cleaner Mac — PRD

The product contract: what 1Cleaner offers, how it removes things and the decisions behind it. Started
2026-10-17 on a developer Mac that kept filling up with build outputs, dependencies, containers and simulators
left by agent-assisted work.

## Problem and positioning

A local, honest alternative to CleanMyMac: show what takes disk space, explain each finding and remove what the
user chooses — safely. A cleaner **for everyone**: **Everyday Cleaner** covers ordinary Mac
junk, and the built-in **Developer Cleaner** is what sets it apart. Success = real reclaimed space, nothing valuable lost, responsive scans on large developer machines.
Never promise a faster Mac, malware detection or a "health score".

## Key decisions (2026-10-17 and later)

1. **Distribution:** notarized Developer ID direct download, **no App Sandbox** (the sandbox blocks
   `~/Library/Developer`, the Docker socket, `xcrun simctl` and projects anywhere in the home folder).
   Free, no paywall, open source under GPL-3.0; optional donations.
2. **Everything file-based goes to the Trash**, after an explicit confirmation listing what will move. Apps
   that belong to the system (installed with a package) are moved by Finder after macOS asks for the
   administrator password.
3. **Docker and simulators** cannot go to the Trash: they are removed by the tool itself (`docker rm`,
   `docker rmi`, `docker volume rm`, `docker builder prune`, `xcrun simctl delete`, `xcrun simctl runtime delete`)
   after a separate red confirmation that says it cannot be undone. Volumes: only volumes no container uses are listed, with a red "may hold a database" warning.
4. **Trash does not free space** until emptied. The result screen says so and offers **Empty Trash…** with its
   own confirmation (empties the whole Trash, like Finder). The Trash is also a scan category.
5. **Never touched**: iCloud and file-sync service data (`KnownLocations.syncServiceFolders`:
   CloudKit, `com.apple.bird`, CloudDocs, FileProvider, Mobile Documents, CloudStorage); removing it can break
   files in iCloud Drive. Results from any scanner that touch these paths are dropped.
6. **Nothing is preselected** (changed on 2026-10-17, replacing "safe is selected"): after a scan
   every item is unchecked, so a needed folder can't slip into a cleanup unnoticed. The person checks items
   or uses Select All per category. Rows show the project's last change, last use or age to help decide.
   Leaving a screen with checked items asks first: *Clean…*, *Clear Selection* (then go),
   or *Cancel* (stay), so items checked on one screen are never cleaned unnoticed from another.

## 1.0 scope

### Developer Cleaner

| Category | What is found | Removal |
| --- | --- | --- |
| Project build folders | In scan folders (default: home): `node_modules` (next to `package.json`), `.next`, `.nuxt`, `.svelte-kit`, `.turbo`, `.parcel-cache`, SwiftPM `.build`, Gradle `build`/`.gradle` (next to `build.gradle[.kts]`/`settings.gradle[.kts]`), Xcode `build` (next to `.xcodeproj`, with Xcode's own output inside), Rust/Maven `target`, CocoaPods `Pods`, Flutter `.dart_tool`/`build`, Python `.venv`/`venv` (with `pyvenv.cfg`). A `build` folder holding files git tracks is Ask AI and its row says how many | Trash |
| Git worktrees | Linked worktrees (`git worktree add`) of the repositories in the scan folders, wherever they are (`.git/worktrees`), grouped by repository; never the main copy, one that holds another repository, or one in a file-sync folder. Ask AI when everything is committed, Risky with uncommitted changes, commits on no branch, a submodule checked out or when git can't tell (git runs without the repository's hooks, fsmonitor or filters); locked when any file outside dependency and build folders changed in the last day or when locked in git, both checked again right before removal, and removed only as the scan saw it. Not movable to another disk. Removal moves the worktree folder and its `.git/worktrees/<name>` folder to the Trash; the branch stays | Trash |
| Xcode | DerivedData per project, Xcode caches, Previews, device support files, XCTest clones, device logs, Archives, other copies of Xcode in /Applications (not the selected one) | Trash |
| Simulators | Devices (one virtual phone with its apps and data; removing keeps its iOS) and runtimes (an iOS version; its devices stop working until it's downloaded again), explained in a Device/Runtime legend; booted devices are shown but locked | `simctl` |
| Android | NDK versions, SDK build tools and platforms, Gradle-downloaded JDKs, Gradle caches, wrapper distributions, daemon logs, Android cache, Android Studio caches (Ask AI: they hold Local History), emulators (AVD), SDK system images | Trash |
| Package caches | npm, Yarn, pnpm store, Bun, Homebrew, pip, uv, Poetry, CocoaPods, SwiftPM, Carthage, Go build cache and modules (made writable before the Trash), Cargo downloads, index and git dependencies, Dart/Flutter pub, NuGet, node-gyp, Electron, Playwright, Puppeteer, Deno, Maven `~/.m2` | Trash |
| Editors | VS Code and Cursor caches, JetBrains caches (Ask AI: they hold the IDE's Local History) | Trash |
| Docker | Stopped containers; images no running container uses (an image used by stopped containers removes them with it, the row and the confirmation say so); the whole build cache; volumes no container uses. A summary shows Docker's space per type and the Docker Desktop disk image size. Images of running containers and attached volumes are never offered. Container logs are not handled (only inside Docker's VM). Daemon not running = category says so; the app never starts Docker | Docker CLI |
| AI models | Ollama models, LM Studio models, Hugging Face models (one row per model) | Trash |
| AI agents | Per agent (Claude, ChatGPT & Codex, Cursor, Antigravity & Gemini, Qwen Code, Windsurf, Kiro, Trae, Continue, Aider, OpenCode; Cline, Roo Code, Kilo Code task histories in VS Code-based editors). Safe: Claude's VM image (locked while Claude runs), editor state of deleted projects, old extension versions no editor list uses. Ask AI: Gemini CLI and Qwen Code temp folders (chat history and checkpoints), Claude Code sessions per project, Codex sessions per month, archived sessions, migration backups and *.bak files, Cursor state backup and agent chats, Antigravity backup and browser profile, agent extension task histories, and all data of agents no longer installed. Sessions and data where a file changed in the last day are locked (folder dates don't count: a cleanup inside isn't use). Live databases and settings are never offered | Trash |

### Everyday Cleaner

| Category | What is found | Removal |
| --- | --- | --- |
| Applications | Apps in /Applications and ~/Applications (one folder deep) with their own files in ~/Library matched by bundle id: Application Support, Caches, Preferences (+ByHost), Saved Application State, HTTPStorages, WebKit, Logs, Application Scripts, LaunchAgents, Cookies; with Full Disk Access the app container, its extensions' containers (`Containers/<id>.*`), its app groups from the code signature and `Group Containers` named after its bundle id — never a group another installed app also declares (Office) or another app's container; exact app-name folders for names of 4+ letters. Size, last opened, every path on hover. Apple apps, Xcode, 1Cleaner and running apps are not offered | Trash |
| Removed apps' leftovers | Files in ~/Library (Application Support, Preferences, Saved Application State, HTTPStorages, WebKit, Application Scripts, Containers with Full Disk Access, LaunchAgents whose program is gone) named by a bundle id that no installed app, LaunchServices or running process has; not shown when an app of the same vendor is installed or anything changed in the last 30 days; helper/extension ids fold into their app's row. Caches and Logs stay in their own categories | Trash |
| App caches | `~/Library/Caches/*` per app, except dev and browser caches listed elsewhere; Mail attachment copies; Chromium/Electron web caches inside an app's Application Support folder (Cache, Code Cache, GPUCache, Dawn/Shader caches, Service Worker cache), locked while that app runs; with Full Disk Access, App Store apps' caches in `Containers/*/Data/Library/Caches` and `Group Containers/*/Library/Caches` (Apple's own: Ask AI) | Trash |
| Logs | `~/Library/Logs/*` | Trash |
| Browser caches | Cache folders only (Safari, Chrome, Edge, Brave, Arc, Firefox, Opera, Vivaldi, Yandex), locked while that browser runs. Never cookies, history, passwords or profiles | Trash |
| Installers | `.dmg`, `.pkg`, `.mpkg`, `.xip` in Downloads and Desktop | Trash |
| Old downloads | Top-level items in Downloads added 90+ days ago (installers and files ≥ 200 MB stay in their own categories) | Trash |
| Temporary files | System /tmp and this user's macOS temp folder: items where nothing changed for 3+ days (Safe); ~/tmp, ~/temp: items untouched for 30+ days (Ask AI). A recently changed folder lists its old subfolders (two levels) and groups its old loose files into one row; macOS's own temp entries (com.apple.*, NSIRD_*) are skipped. Only file dates count, and an item that changes while it's measured is dropped. Simulator devices left in temporary device sets show as named devices (Ask AI, running ones locked); Claude Code's `/private/tmp/claude-<uid>` folders show as Claude Code session files per project (Ask AI) | Trash |
| Large files | Files ≥ 200 MB in the home folder (outside Library and app bundles), with last-opened date | Trash |
| Duplicates | Exact copies (same size, SHA-256) of files ≥ 1 MB found by the same walk, one row per file; opening it lists every copy (path, created date, the oldest marked) to check; one copy of each set always stays (the last unchecked copy can't be checked). Size = space freed by keeping one copy. Not offered: hard links, APFS clones (removing them frees nothing), files only in iCloud (reading would download them), files inside git repositories (project files) | Trash |
| iPhone & iPad | Finder device backups (name, iOS version, backup date; needs Full Disk Access) and downloaded iOS/iPadOS updates | Trash |
| Trash | Current Trash size | Empty Trash… |

**Later, not in 1.0:** similar photos, Photos library, mail attachments, language files, Time Machine local
snapshots, scheduled reminders, menu bar widget, paywall. (Localization shipped in 1.1.0;
duplicates and the uninstaller with leftovers in 1.2.0; git worktrees in 1.3.0.)

**Languages (1.1.0):** en, ru, uk, de, nl, es, pt-BR, fr, it, pl, tr, ja, ko, zh-Hans, zh-Hant,
id, vi. The app follows macOS's language; About › Language picks another one for 1Cleaner only (applies after a
restart, with a Restart button). Arabic is left out on purpose (right-to-left layout). Pipeline and rules:
`tools/l10n/README.md`.

## Experience

1. **Dashboard** (the home screen shows the value of using the app over time): tiles
   *Cleaned with 1Cleaner* (all-time size moved to the Trash or removed by tools, number of cleanups and items,
   since the first launch), *Last scan* (when, size found, duration) and *Macintosh HD* (available of total,
   red under 10% free); Developer and Everyday cards (before a new scan they show the last scan's sizes, dimmed);
   *Recent cleanups* (date, items, size); one **Scan** button (scans everything; categories fill in as they
   finish). Optional Full Disk Access banner (Safari and a few protected caches); never blocks scanning.
   Stats stay on this Mac (UserDefaults); a stopped scan doesn't replace the last full one.
2. **Sidebar:** Dashboard, then Developer and Everyday categories with their found size; a spinner while scanning.
3. **Category screen:** items with checkbox, name, detail (project path, runtime, age), size, a short "what it
   is / what happens if removed" note per category, Reveal in Finder and a ••• menu. Search and a **size quick
   filter** (All / 10 MB+ / 100 MB+ / 1 GB+, default 10 MB+, remembered) in the toolbar; the list says how many
   smaller items are hidden, with Show All. Select All / None act only on the items shown.
4. **Safe List**: items and folders that never appear in scans. From a row's ••• or
   right-click menu: *Add to Safe List* (that item) or *Add Project to Safe List* (the build folder's repository
   or project folder — nothing inside it is shown, and the project walk skips it). A **Safe List** section at the
   bottom of the sidebar lists items (title, category, size and date when added, path) and
   folders, adds folders, reveals them in Finder and takes entries off the list. An item taken off is shown again
   at once (its category is scanned again); a folder returns in the next scan. Applies at once.
5. **Bottom bar** (all screens): selected size and count, **Clean…**.
6. **Confirmation sheet:** totals per category, split into "Move to Trash" and, in red, "Remove permanently
   with Docker / Xcode tools — cannot be undone". Cancel is the default button.
7. **Cleaning:** progress per item with Stop (stops after the current item; finished items stay done).
8. **Result:** moved to Trash (size), removed by tools (size), failed/skipped items with reasons, free disk space
   before and now, **Empty Trash…**. Removed items leave the lists; failed ones stay.

**Safety labels**: every row shows a hint; it never selects anything. The mapping lives in
`Core/Safety.swift` and changes only with the maintainer. Above every list a legend says the labels are about how
safe it is to delete an item, each with its meaning in a few words ("Risky" was read as "the
app is risky").

| Label | Meaning | Items |
| --- | --- | --- |
| Safe | Comes back on its own; only rebuild/download time is lost | simulator devices whose iOS is gone (can't run), removed apps' leftovers with only settings and caches, app (non-Apple), browser, editor and web caches, logs, package caches, DerivedData, Xcode and simulator caches, device support, Gradle caches and wrappers, project build folders, Docker build cache, iOS updates, Mail attachment copies |
| Ask AI | Probably fine, depends on how it's used | build folders holding files git tracks, JetBrains and Android Studio caches (they hold Local History), simulator devices (one disposable virtual phone), removed apps' leftovers with signs of personal data, `com.apple.*` caches, old downloads, installers, NDK/SDK/JDK, AI models, Docker images and stopped containers, simulator runtimes, other Xcode copies, pnpm store, Playwright/Puppeteer, Xcode Archives except each app's newest (the build comes back from its git tag, only its crash symbols don't), duplicates, Poetry cache (holds virtual environments), Apple's caches inside containers |
| Risky | May hold data that exists nowhere else | apps with their data, iPhone/iPad backups, the newest Xcode Archive of each app, Docker volumes, Android emulators, large files, Maven repository |

Leftovers' personal-data signs: saved passwords (`Login Data`), bookmarks, browsing
history, databases ≥ 512 KB, or files in a Documents folder, inside Application Support or the app container
(web cache folders skipped). Cookies and website storage of a removed app don't count. The row says what was
found ("has saved passwords, databases") or "settings and caches only".

*Ask AI about N items* in a category header copies one question about every Ask AI row shown (up to 150),
answered as a table: Remove / Keep / Check with a reason.

*Ask AI* on a row (and *Copy for AI* in every row's menu) copies a question for any AI assistant: the item,
category and note, safety hint, size, last change, how 1Cleaner removes it (Trash or the exact tool command),
paths, the 20 largest entries of a folder with sizes, macOS version, and four questions (what it is, what
breaks, how to restore, recommendation), answered in the Mac's first language. Built locally; nothing is sent.
The confirmation sheet warns when Risky items are selected.

**Storage** (a storage analyzer with drill-down): sidebar *Storage* and a dashboard panel
*What takes your disk* (stacked bar + legend; the last analysis is saved). Three levels: kind of data
(Applications, Developer, Photos, Videos, Music & Audio, Documents, Archives & Disk Images, iPhone & iPad
Backups, Mail & Messages, App Data & Caches, Trash, Other Files, plus *macOS and System Data* = used space not
measured) → folders holding it (with file counts) → its largest files (≥ 1 MB) with Show in Finder. For
Photos, Videos, Music & Audio, Documents and Archives a folder also lists its biggest subfolders of that kind,
level by level, skipping folders that only lead to one subfolder; each level has its own
file count, total and Show in Finder. Largest files are kept per kind, so one kind never hides another's. Location decides first (an app
bundle, a Photos library, ~/Library/Developer, node_modules, ...), then the file extension. Runs with every full
scan and from *Analyze Again*; read-only; parallel walk of the home folder and /Applications. Without Full
Disk Access, app containers, Mail, Messages and Safari are not read and count as system data.

**Large Folders**: a view-only item in the Everyday group, under Large Files, made by the same Storage walk. It
lists folders that are big because of a mass of small files: files under 1 MB in it, not counting subfolders already
listed, add up to 100 MB or more, number 1,000 or more, and are at least half of what it holds outside those
subfolders. Each row: size, file count, how much the small files take, Show in Finder. A listed folder can hold
another listed folder; folders inside packages (app bundles, Photos libraries, ...) and in /Applications aren't
listed. The sidebar shows how many were found, not a size. Nothing can be selected or removed there.

**Support and About**: the toolbar's right side always shows ♥ *Support* and ⓘ *About*.
Support is a sheet with crypto addresses by network (Ethereum & EVM: Ethereum, Arbitrum, BNB Chain — USDT, USDC,
ETH, BNB; Tron — USDT, TRX; Solana — USDT, USDC, SOL; TON — USDT, TON; Bitcoin — BTC), a QR code made on the Mac,
Copy Address and a wrong-network warning. It also opens once, after the first cleanup that freed space ("12 GB freed.
Support 1Cleaner?"); after that only the heart offers it. About: version, *Check for Updates* (only on request: reads
`onebuckapps.com/1cleaner-mac/version.json`, offers the download page and *Install and Relaunch*: downloads the
release's DMG, checks it, replaces the app and restarts it), free-with-optional-support note, Tell a
friend (share sheet after the explanation), Write to Support, Privacy Policy, Terms, Follow us (YouTube, TikTok,
Telegram, X) and the line's other apps. The app menu has *Check for Updates…* and *Support the Developer…*. No
payments inside the app; a Mac App Store build would leave this out.

In Applications, an installed app's files in ~/Library are shown as **app data**, not leftovers: they are
what the app works with (settings, history, logins), so removing them resets the app.

**Move to Another Disk** (row menu, any file-based item; e.g. old iPhone backups to an external drive): pick a
folder on another disk; 1Cleaner checks space, copies with `ditto`, verifies the copy (same files and total length,
ignoring `.DS_Store`/AppleDouble files that exFAT drives add), and only then moves the original to the Trash. A
failed or stopped copy leaves the original untouched and removes only its own partial copy. Same-disk folders are
refused. Counted in the dashboard as cleaned.

**Rescan one category**: the category screen's Rescan button, a sidebar right-click or
"Scan <category>" on a not-yet-scanned category scans only that area, e.g. Docker after starting it. Project
Builds, Large Files and Duplicates share one walk, so they refresh together. The rescanned category's selection is cleared;
the dashboard keeps the last full scan. After a cleanup that removed Docker containers, Docker is rescanned
automatically so the images they used appear.

Scan **Stop** keeps partial results. Closing the window stops a running scan or cleanup the same way.

## Safety contract

- Only items found by the scan are removed; before each removal the app re-checks the path still exists, is
  not a symlink, has not been replaced and sits inside its expected root (the home folder; other Xcode copies
  in /Applications are the only exception: app bundles there, top level or one folder deep; and items in the
  system /tmp and this user's macOS temp folder).
- Project source, lockfiles, `.git`, credentials, signing keys, volumes attached to containers and running
  simulators are never candidates. Running tools are not stopped by the app.
- Sizes are allocated bytes on disk, hard links counted once per item; APFS clones may make a size look larger
  than what is freed — the result screen reports free space measured before and after.
- No analytics, no account. Scanning and cleaning happen on this Mac only; the app goes online only when the
  person asks: Check for Updates reads `version.json`, Install and Relaunch downloads the DMG.

## Technical notes

- Native SwiftUI, macOS 14+, Swift 6 strict concurrency, light appearance (1Buck brand: orange `#FF6A13`,
  deep orange `#C2410C`, warm background `#F6F4F1`, white surfaces). No third-party dependencies.
- File-system walks run off the main actor with `fts`, bounded parallel sizing, cancellation and periodic
  progress. External tools run with fixed absolute paths, a timeout and no shell.
- Distribution signing (Developer ID + notarization) is a release step; local builds sign to run locally.
