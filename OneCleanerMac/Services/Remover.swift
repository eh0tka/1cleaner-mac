import AppKit
import Darwin
import Foundation
import os

/// Removes one scanned item. Files go to the Trash after re-checking that each path is still the object the
/// scan found; Docker and simulator items are removed by their own tools.
enum Remover {
    enum Outcome: Sendable {
        case movedToTrash
        case removed
        case failed(String)
    }

    static func remove(_ item: CleanupItem) async -> Outcome {
        switch item.removal {
        case .trash(let targets):
            return await moveToTrash(targets)
        case .docker(let operation):
            guard let docker = DockerScanner.executable else {
                return .failed(String(localized: "Docker isn't installed.", comment: "Cleanup failure reason"))
            }
            // Only the daemon on this Mac that the scan read, named in every command so nothing else is reached.
            guard let host = DockerScanner.scannedHost.withLock({ $0 }), await DockerScanner.localHost(docker) == host else {
                return .failed(String(localized: "Docker now uses a different setup than during the scan. Scan again.",
                                      comment: "Cleanup failure reason: the Docker context changed since the scan"))
            }
            let daemon = ["--host", host]
            let changed = Outcome.failed(String(localized: "It changed since the scan. Scan again.",
                                                comment: "Why an item can't be moved to the Trash"))
            // Stopped containers as the scan saw them: one started again since then (its data may be new) stays.
            func stoppedSinceTheScan(_ ids: [String]) async -> Bool {
                guard !ids.isEmpty else { return true }
                guard let scanned = DockerScanner.scannedAt.withLock({ $0 }), let states = try? await ProcessRunner.run(
                    docker, daemon + ["inspect", "--format", "{{.State.Running}}|{{.State.FinishedAt}}"] + ids,
                    timeout: .seconds(60)
                ), states.succeeded else { return false }
                let lines = states.stdout.split(whereSeparator: \.isNewline)
                return lines.count == ids.count && lines.allSatisfy { line in
                    let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
                    // Read to the second: one that stopped within the scan's own second counts as after it.
                    return parts.count == 2 && parts[0] == "false"
                        && DockerScanner.finishedAt(parts[1]).map { $0.addingTimeInterval(1) <= scanned } == true
                }
            }
            switch operation {
            case .container(let id):
                guard await stoppedSinceTheScan([id]) else { return changed }
                return await runTool(docker, daemon + ["rm", id], timeout: .seconds(300))
            case .image(let id, let stoppedContainers, let references):
                // Started from this image since the scan: its stopped containers aren't removed either.
                guard let running = try? await ProcessRunner.run(
                    docker, daemon + ["ps", "-q", "--no-trunc", "--filter", "ancestor=\(id)", "--filter", "status=running"],
                    timeout: .seconds(60)
                ), running.succeeded, running.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return changed
                }
                // Names can move to another image (a new build takes `latest`): each must still name this one.
                func namesStillThisImage() async -> Bool {
                    guard let named = try? await ProcessRunner.run(
                        docker, daemon + ["image", "inspect", "--format", "{{.Id}}"] + references, timeout: .seconds(60)
                    ), named.succeeded else { return false }
                    return named.stdout.split(whereSeparator: \.isNewline).map(String.init)
                        == Array(repeating: id, count: references.count)
                }
                // A container selected on its own may already be gone (`inspect` then fails): checked one by one.
                var present: [String] = []
                for container in stoppedContainers {
                    if let found = try? await ProcessRunner.run(docker, daemon + ["inspect", "--format", "{{.Id}}", container],
                                                                timeout: .seconds(60)), found.succeeded {
                        present.append(container)
                    }
                }
                guard await stoppedSinceTheScan(present) else { return changed }
                // Tagged in two repositories, Docker removes an image only by its names (by id it asks for force):
                // checked right before, and before the containers go. With stopped containers left the last name
                // stays, and the image goes by id below.
                if references.count > 1 {
                    guard await namesStillThisImage() else { return changed }
                    _ = try? await ProcessRunner.run(docker, daemon + ["rmi"] + references, timeout: .seconds(300))
                }
                for container in present {
                    _ = try? await ProcessRunner.run(docker, daemon + ["rm", container], timeout: .seconds(300))
                }
                // Gone only when Docker answers and no longer lists it (a daemon that stopped answering isn't).
                if references.count > 1, let listed = try? await ProcessRunner.run(
                    docker, daemon + ["image", "ls", "-q", "--no-trunc"], timeout: .seconds(60)
                ), listed.succeeded, !listed.stdout.split(whereSeparator: \.isNewline).contains(where: { $0 == id }) {
                    return .removed
                }
                return await runTool(docker, daemon + ["rmi", id], timeout: .seconds(300))
            case .volume(let name, let created):
                guard let now = try? await ProcessRunner.run(
                    docker, daemon + ["volume", "inspect", "--format", "{{.CreatedAt}}", name], timeout: .seconds(60)
                ), now.succeeded, now.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == created else {
                    return .failed(String(localized: "It changed since the scan. Scan again.",
                                          comment: "Why an item can't be moved to the Trash"))
                }
                return await runTool(docker, daemon + ["volume", "rm", name], timeout: .seconds(300))
            case .buildCache:
                // Docker's own prune, through the daemon above: with BuildKit on, `docker builder` goes to buildx,
                // which may use another builder (`docker buildx use`, a remote or cloud one) than this Mac's daemon.
                return await runTool(docker, daemon + ["builder", "prune", "--all", "--force"], timeout: .seconds(300),
                                     extraEnvironment: ["DOCKER_BUILDKIT": "0"])
            }
        case .simulatorDevice(let udid, let lastUsed):
            if await SimulatorScanner.isRunning(device: udid) {
                return .failed(String(localized: "Running. Shut it down to remove it.",
                                      comment: "Why a running simulator device can't be selected"))
            }
            if await SimulatorScanner.usedSinceScan(device: udid, lastUsed: lastUsed) {
                return .failed(String(localized: "It changed since the scan. Scan again.",
                                      comment: "Why an item can't be moved to the Trash"))
            }
            return await runTool(SimulatorScanner.xcrun, ["simctl", "delete", udid], timeout: .seconds(180))
        case .simulatorRuntime(let id):
            if await SimulatorScanner.isRunning(runtime: id) { return .failed(SimulatorScanner.runtimeRunningReason) }
            return await runTool(SimulatorScanner.xcrun, ["simctl", "runtime", "delete", id], timeout: .seconds(600))
        case .emptyTrash:
            return .failed(String(localized: "The Trash is emptied with Empty Trash.",
                                  comment: "Cleanup failure reason. Empty Trash is the button's title."))
        }
    }

    private static func runTool(
        _ executable: String, _ arguments: [String], timeout: Duration, extraEnvironment: [String: String] = [:]
    ) async -> Outcome {
        do {
            let output = try await ProcessRunner.run(executable, arguments, timeout: timeout, extraEnvironment: extraEnvironment)
            return output.succeeded ? .removed : .failed(output.errorMessage)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func moveToTrash(_ targets: [FileTarget]) async -> Outcome {
        // Parts an earlier attempt moved before another part failed are skipped, so trying again finishes the item;
        // a part gone for any other reason stops it. Everything else is checked first, so a changed part stops the
        // item before anything moves.
        let present = targets.filter { target in !(movedTargets.withLock { $0.contains(target) } && !exists(target.path)) }
        guard !present.isEmpty else {
            return .failed(String(localized: "It no longer exists.", comment: "Why an item can't be moved to the Trash"))
        }
        for target in present {
            if let problem = problem(with: target) { return .failed(problem) }
            if let problem = await runningProblem(target.path) ?? usedByRunningApp(target) { return .failed(problem) }
        }
        let apps = present.map(\.path).filter { $0.hasSuffix(".app") }
        for target in present {
            // Checked again right before moving: the administrator password for an earlier part can take a while,
            // and the app whose data this is may have been started meanwhile.
            if let problem = problem(with: target) { return .failed(problem) }
            for path in Set(apps + [target.path]) {
                if let problem = await runningProblem(path) { return .failed(problem) }
            }
            if let problem = usedByRunningApp(target) { return .failed(problem) }
            // Go's module cache is read-only; without write access Finder couldn't empty the Trash afterwards.
            if target.path == NSHomeDirectory() + "/go/pkg/mod" {
                makeWritable(target.path)
                // The walk took a while: the same check once more, right before the move.
                if let problem = problem(with: target) { return .failed(problem) }
            }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: target.path), resultingItemURL: nil)
            } catch let error as CocoaError where error.code == .fileWriteNoPermission && isApplicationsApp(target.path) {
                // Apps installed with a package belong to the system: Finder moves them after the administrator
                // password, the same way as dragging them to the Trash.
                if let failure = await trashWithFinder(target.path) { return .failed(failure) }
            } catch {
                return .failed(error.localizedDescription)
            }
            movedTargets.withLock { _ = $0.insert(target) }
        }
        return .movedToTrash
    }

    /// Scan folders on other disks (`/Volumes/<disk>/…`), kept current by `AppModel`.
    static let scanFoldersOnOtherDisks = OSAllocatedUnfairLock<[String]>(initialState: [])

    /// Parts this app moved to the Trash since it started.
    private static let movedTargets = OSAllocatedUnfairLock(initialState: Set<FileTarget>())

    /// An app or an Android emulator started after the scan locked nothing: checked again right before removal.
    static func runningProblem(_ path: String) async -> String? {
        let running: Bool
        if path.hasSuffix(".app") {
            // A bundle already moved to the Trash isn't running from here (and nil would match every app whose
            // bundle can't be resolved, such as the Android emulator).
            guard let resolved = XcodeScanner.resolved(path) else { return nil }
            running = NSWorkspace.shared.runningApplications.contains { app in
                app.bundleURL.flatMap { XcodeScanner.resolved($0.path) } == resolved
            }
        } else if path.hasSuffix(".avd") {
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            running = await AndroidScanner.runningAVDs().map { $0.contains(name) } ?? true
        } else if let appName = EditorsScanner.runningOwner(of: path) ?? BrowserCachesScanner.runningOwner(of: path) {
            return String(localized: "Running. Quit \(appName) to clean its cache.",
                          comment: "Why a browser's cache row can't be selected; %@ is a browser name")
        } else {
            return nil
        }
        return running ? String(localized: "Running. Quit it to remove it.", comment: "Why a running app can't be selected") : nil
    }

    /// An app that uses this part (Claude with its virtual machine, an app with web caches in its data) started
    /// after the scan.
    static func usedByRunningApp(_ target: FileTarget) -> String? {
        guard !target.usedWhileRunning.isEmpty else { return nil }
        let running = NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier.map(target.usedWhileRunning.contains) == true
                || app.localizedName.map { target.usedWhileRunning.contains($0.lowercased()) } == true
        }
        return running ? String(localized: "Running. Quit it to remove it.", comment: "Why a running app can't be selected") : nil
    }

    private static func passesThroughLink(_ path: String) -> Bool {
        var prefix = ""
        for part in path.split(separator: "/") {
            prefix += "/" + part
            var info = stat()
            if lstat(prefix, &info) != 0 || (info.st_mode & S_IFMT) == S_IFLNK { return true }
        }
        return false
    }

    /// At least one of these files is still exactly what the scan found (runs off the main thread).
    static func anyUnchanged(_ targets: [FileTarget]) async -> Bool {
        targets.contains { problem(with: $0) == nil }
    }

    private static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// An app bundle in /Applications, top level or one folder deep: the one place outside home the uninstaller and
    /// other copies of Xcode reach. Only a real folder: a Finder alias named `X.app` is a file.
    private static func isApplicationsApp(_ path: String) -> Bool {
        path.hasPrefix("/Applications/") && path.hasSuffix(".app")
            && (2...3).contains(path.split(separator: "/").count) && FileInfo.isDirectory(path)
    }

    /// Finder asks for the administrator password itself; nil when the app is in the Trash.
    private static func trashWithFinder(_ path: String) async -> String? {
        let script = ["on run argv", "tell application \"Finder\" to delete (POSIX file (item 1 of argv) as alias)", "end run"]
        do {
            let output = try await ProcessRunner.run(
                "/usr/bin/osascript", script.flatMap { ["-e", $0] } + [path], timeout: .seconds(600)
            )
            if output.succeeded, !FileInfo.exists(path) { return nil }
            if output.stderr.contains("(-128)") {
                return String(localized: "The administrator password wasn't entered.",
                              comment: "Cleanup failure reason: macOS asked for the password to remove an app and it was cancelled")
            }
            // Automation not allowed: the same advice as for Empty Trash.
            if output.stderr.contains("(-1743)") { return SystemAccess.trashFailure(output) }
            var message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = message.range(of: "got an error: ") { message = String(message[range.upperBound...]) }
            if let range = message.range(of: #"\s*\(-?\d+\)$"#, options: .regularExpression) { message.removeSubrange(range) }
            return String(localized: "Finder couldn't move it to the Trash: \(message)",
                          comment: "Cleanup failure reason. The placeholder is Finder's own message (a sentence).")
        } catch {
            return error.localizedDescription
        }
    }

    /// Gives the owner write access to every folder and file inside, walking like the scans do: never through a
    /// symbolic link, never onto another disk.
    private static func makeWritable(_ path: String) {
        FileSizer.walk(path) { entry in
            if Task.isCancelled { return .stop }
            let info = Int32(entry.pointee.fts_info)
            if info == FTS_D || info == FTS_F, let stat = entry.pointee.fts_statp?.pointee, stat.st_mode & S_IWUSR == 0 {
                _ = chmod(entry.pointee.fts_path, (stat.st_mode & 0o7777) | S_IWUSR)
            }
            return .continue
        }
    }

    /// Where moving to the Trash is allowed at all: inside the home folder, app bundles in /Applications, temp
    /// items in the system /tmp and this user's macOS temp folder, and on other disks only inside scan folders the
    /// person added (the startup disk's own link in /Volumes fails the symbolic-link check).
    static func isInAllowedPlace(_ path: String, scanFoldersOnOtherDisks folders: [String]) -> Bool {
        let parts = path.split(separator: "/")
        let otherDisk = path.hasPrefix("/Volumes/") && parts.count >= 3 && folders.contains { path.hasPrefix($0 + "/") }
        return (path.hasPrefix(NSHomeDirectory() + "/") || isApplicationsApp(path)
                || TemporaryScanner.systemRoots.contains { path.hasPrefix($0 + "/") } || otherDisk)
            && !path.contains("/../") && !path.hasSuffix("/..")
    }

    /// Why a path must not be moved, or nil when it is still exactly what the scan found.
    static func problem(with target: FileTarget) -> String? {
        let path = target.path
        guard isInAllowedPlace(path, scanFoldersOnOtherDisks: scanFoldersOnOtherDisks.withLock { $0 }) else {
            return String(localized: "It is outside your home folder.",
                          comment: "Why an item can't be moved to the Trash")
        }
        var info = stat()
        guard lstat(path, &info) == 0 else {
            return String(localized: "It no longer exists.", comment: "Why an item can't be moved to the Trash")
        }
        if (info.st_mode & S_IFMT) == S_IFLNK {
            return String(localized: "It is a symbolic link.", comment: "Why an item can't be moved to the Trash")
        }
        guard info.st_dev == target.device, info.st_ino == target.inode,
              target.content == nil || target.content == FileTarget.ContentStamp(info),
              target.tree == nil || target.tree.map({ tree in
                  let now = Mover.fingerprint(path)
                  return now.unreadable == 0 && now == tree
              }) == true else {
            return String(localized: "It changed since the scan. Scan again.",
                          comment: "Why an item can't be moved to the Trash")
        }
        let parent = (path as NSString).deletingLastPathComponent
        guard let resolved = realpath(parent, nil) else {
            return String(localized: "Its folder can't be read.", comment: "Why an item can't be moved to the Trash")
        }
        defer { free(resolved) }
        // A path spelled with other capitals than on disk resolves to the same folder on a case-insensitive disk;
        // then no part of it may be a link (on a case-sensitive disk `Link` → `link` would be one).
        let canonical = String(cString: resolved)
        if canonical != parent && (canonical.lowercased() != parent.lowercased() || passesThroughLink(parent)) {
            return String(localized: "Its path goes through a symbolic link.",
                          comment: "Why an item can't be moved to the Trash")
        }
        // Locked with `git worktree lock` after the scan.
        if let lock = target.gitLockFile, FileInfo.exists(lock) {
            return String(localized: "Locked in git (git worktree lock).",
                          comment: "Why a git worktree can't be selected; keep the command as is")
        }
        let dayAgo = Date().addingTimeInterval(-86_400)
        let projectChanged = target.projectQuietForADay && {
            let newest = ProjectScanner.newestChange(inWorkingCopy: path)
            // A repository of its own put inside after the scan stops it too.
            return !newest.complete || newest.holdsClone
                || (ProjectScanner.gitDates(path) + [newest.date].compactMap { $0 }).contains { $0 > dayAgo }
        }()
        if projectChanged || target.quietForADay && TemporaryScanner.newestChange(path).map({ $0 > dayAgo }) == true {
            return String(localized: "Changed in the last day; a session may be running.",
                          comment: "Why an AI agent's session history can't be selected")
        }
        return nil
    }
}
