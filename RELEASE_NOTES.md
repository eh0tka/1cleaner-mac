# 1Cleaner for Mac — Release Notes

## 1.3.3

- Large Folders, in Everyday under Large Files: the folders that are big because of thousands of small files, like
  caches, node_modules and exported image sets, with their size and file count. View only; Show in Finder opens
  one.

## 1.3.2

- JetBrains and Android Studio caches are marked Ask AI: they hold the IDE's Local History, earlier versions of
  your files.
- If macOS can't start the updated copy, 1Cleaner stays open and says so.

## 1.3.1

- Links in About show the pointing hand when you hover over them.

## 1.3.0

- Install and Relaunch: an update found with Check for Updates downloads, is checked and installed, and 1Cleaner
  restarts, without a visit to the website.
- Git Worktrees: extra working copies of your repositories, left by AI agents and parallel branches, grouped by
  repository; each one shows its branch, where it is, when it last changed and whether everything is committed.
- Safer uninstall: another app's launch agents and app groups, and data shared with a second copy of the app,
  always stay; a folder named like the app that may belong to another app stays too, and the app's row says so.
- Quitting during a cleanup or a move asks first; Stop and Quit finishes the current item and removes an unfinished
  copy.
- Files on other disks in your own scan folders can be removed.
- Editor caches are locked while the editor is running; a simulator runtime is locked while a simulator on it runs.
- Docker is cleaned only on this Mac: with a remote Docker context nothing is listed or removed.
- Docker images named in several repositories can be removed. A container started again since the scan, an image
  used again (with its stopped containers) and a volume made again under the same name stay. The build cache is
  cleaned only in Docker on this Mac, never on another builder.
- Gemini CLI and Qwen Code folders hold chat history: they are now Ask AI and locked while in use.
- Duplicates: one copy always stays, also when copies are checked in Large Files or sit in a checked folder; a copy
  changed after the scan isn't removed.
- Large files, installers, old downloads, temporary files, AI agents' data and iPhone backups changed since the scan
  aren't removed; scan again to see them.
- Temporary files unpacked from an archive count as new from the day they were unpacked, not by their old dates; a
  ~/tmp that links to another folder isn't scanned.
- A build folder holding files git tracks is marked Ask AI, and its row says how many.
- Leftovers of removed apps changed in the last 30 days are not offered, wherever the change is inside, and
  leftovers changed after the scan aren't removed.
- AI agents installed with nvm, fnm, pnpm, asdf or mise, and Continue in an editor, count as installed.
- Tools' own folders in the home folder (like ~/.claude) aren't searched for project builds.
- Files kept only in iCloud aren't listed as large files.
- The Safe List also protects a folder that sits inside an offered item.
- The selected Xcode behind a link is never offered; a running Xcode or Android emulator is locked.
- Move to Another Disk never replaces or removes anything already in the destination, and stops when the original
  changes during the copy, holds files it can't read, or any part of a file can't be copied.
- A command-line tool that stops answering is stopped after its time limit.
- Scanning one category again can be stopped too.
- Trying again finishes an item that was only partly moved to the Trash.
- Settings no longer claim that 1Cleaner never reads files: it reads them only on this Mac, for example to compare
  duplicates.

## 1.2.0

- Duplicates: every file with copies is one row; open it to see all copies and choose which to remove. One copy
  always stays.
- Apps installed by a package can be removed too: macOS asks for the administrator password.
- App Caches include the caches of App Store apps (with Full Disk Access).
- More developer caches: Go modules, Cargo index and git dependencies, Dart and Flutter packages, NuGet, Poetry.
- Uninstalling an app also removes its shared app data, cookies and extensions' data (with Full Disk Access);
  data another installed app uses stays.
- iCloud and file-sync service data is never shown or removed.

## 1.1.4

- The support window is wider and always shows everything at once.

## 1.1.3

- The Safe, Ask AI and Risky labels now explain themselves: they show how safe it is to delete each item.
- Leaving a section with items checked asks first: clean them, clear the selection, or stay.
- The support window fits any screen: long addresses no longer get cut off.

## 1.1.2

- Full Disk Access is easier to find: the Dashboard asks for it at the top, and Storage has a button to open
  the setting right next to its note.

## 1.1.1

- The support window opens only once, after your first cleanup. After that, support is always one click away
  on the heart at the top right.

## 1.1.0

- 1Cleaner speaks 17 languages: English, Russian, Ukrainian, German, Dutch, Spanish, Brazilian Portuguese,
  French, Italian, Polish, Turkish, Japanese, Korean, Simplified and Traditional Chinese, Indonesian and Vietnamese.
- It follows your Mac's language; About › Language switches 1Cleaner to another one.
- Questions copied for an AI assistant are written in your language.
- Docker image ages are shown in your language.

## 1.0.0

- Dashboard: everything cleaned with 1Cleaner, the last scan, free disk space, what takes your disk and recent
  cleanups.
- Storage: see your disk by kind of data (apps, developer data, photos, videos, documents and more), then the
  folders, subfolders and largest files behind each one.
- Developer Cleaner: project build folders (node_modules, .next, .build, Gradle build, Rust/Maven target, Pods,
  Flutter, Python venvs), Xcode DerivedData, caches, previews, device support and archives, simulator devices and
  runtimes, other Xcode copies, Android/Gradle caches, NDKs, SDK tools, emulators and system images, local AI
  models, AI agents' sessions, backups and leftovers (Claude, Codex, Cursor, Antigravity and more), package-manager caches, editor caches, Docker stopped containers, unused images, build cache and unused
  volumes, with a summary of where Docker's space goes.
- Temporary files in /tmp, the macOS temp folder and your own ~/tmp, only when untouched for days.
- Everyday Cleaner: uninstall apps with their data, leftovers of apps you already removed, app caches (including
  web caches inside apps' data), logs, browser caches, installers, old downloads, large files, iPhone and iPad
  backups and updates, and the Trash.
- Safe by default: nothing is selected for you; files go to the Trash after a confirmation; Docker and
  simulators are removed by their own tools after a separate warning.
- Result with space moved to the Trash, removed by tools, free space before and after, and Empty Trash.
- Move to Another Disk: copy something big to an external drive, check the copy, then send the original to the
  Trash.
- Rescan a single category, for example Docker after starting it.
- Every item is labeled Safe, Ask AI or Risky; Ask AI copies a ready question about the item for any AI
  assistant, or one question about the whole list.
- Size quick filter and search in every list; small items are hidden by default.
- Safe List: keep an item or a whole project out of all future scans; see and edit it in its own section.
- Scan folders in Settings; optional Full Disk Access.
- Free, with optional crypto support of the developer (heart at the top right, and after a cleanup).
- About: check for updates when you want, privacy policy, support, share with a friend, follow us.
