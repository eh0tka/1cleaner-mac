import Darwin
import Foundation

/// Extra working copies of git repositories (`git worktree add`), often left behind by AI agents and parallel
/// branches. They are found through each repository the project walk saw: its
/// `.git/worktrees/<name>` folder knows where every linked worktree lives, also outside the scan folders
/// (`~/.cursor/worktrees`, a temp folder). The repository's main copy is never offered.
///
/// Removing one moves the worktree folder and its folder inside `.git/worktrees` to the Trash, which is what
/// `git worktree remove` does but can be put back. The branch and its commits stay in the repository; changes not
/// committed in the worktree, and files git ignores there (`.env`, build output), go with the folder.
enum WorktreeFinder {
    struct Worktree: Sendable {
        let repository: String
        let path: String
        /// `.git/worktrees/<name>` in the main repository: the worktree's HEAD, index and log.
        let metadata: String
        let branch: String?
        let lockedInGit: Bool
    }

    /// Git from Xcode or its command line tools, or Homebrew; never the `/usr/bin/git` stub, which asks to install
    /// the developer tools when they're missing.
    static var git: String? {
        ProcessRunner.firstExecutable([
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
        ])
    }

    /// The linked worktrees of a repository whose folder still exists and still belongs to it.
    static func worktrees(of repository: String) -> [Worktree] {
        let folder = repository + "/.git/worktrees"
        return FileInfo.children(folder).filter { !$0.hasPrefix(".") }.compactMap { name in
            let metadata = folder + "/" + name
            guard var gitFile = read(metadata + "/gitdir") else { return nil }
            // Git 2.48+ can write it relative to the metadata folder (`worktree.useRelativePaths`).
            if !gitFile.hasPrefix("/") { gitFile = URL(fileURLWithPath: metadata + "/" + gitFile).standardized.path }
            guard (gitFile as NSString).lastPathComponent == ".git" else { return nil }
            let path = (gitFile as NSString).deletingLastPathComponent
            // A folder gone (`git worktree prune` cleans that up) or one whose `.git` points elsewhere now. A
            // worktree folder that holds the repository itself is never offered: the main copy would go with it.
            // Compared as resolved paths, so a link on the way (/tmp, a linked projects folder) can't hide it.
            guard FileInfo.isDirectory(path), !FileInfo.isSymbolicLink(path), pointsBack(gitFile, to: metadata),
                  let real = XcodeScanner.resolved(path), let realRepository = XcodeScanner.resolved(repository),
                  let realMetadata = XcodeScanner.resolved(metadata),
                  real != realRepository, !realRepository.hasPrefix(real + "/") else { return nil }
            let head = read(metadata + "/HEAD") ?? ""
            let branch = head.hasPrefix("ref: refs/heads/") ? String(head.dropFirst("ref: refs/heads/".count)) : nil
            // Kept as spelled on disk (`~/library/…` written by hand is `~/Library/…`), so every later check, here
            // and in AppModel, sees the real path.
            return Worktree(repository: repository, path: real, metadata: realMetadata, branch: branch,
                            lockedInGit: FileInfo.exists(metadata + "/locked"))
        }
    }

    /// A repository's own config can name a program for git to run (`core.fsmonitor`); never for this app.
    static let gitSafety = ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"]

    /// Files changed, added or deleted and not committed (untracked files count, ignored ones don't); nil when git
    /// couldn't tell. Git runs without taking its optional locks, so it never touches the repository, and never
    /// goes into submodules (the caller treats a copy holding one as unknown).
    static func uncommittedChanges(_ worktree: Worktree, git: String) async -> Int? {
        guard let filters = await filtersOff(worktree, git: git),
              let output = try? await ProcessRunner.run(
                  git, gitSafety + filters + ["-C", worktree.path, "status", "--porcelain",
                                              "--untracked-files=normal", "--ignore-submodules=all"],
                  timeout: .seconds(60), extraEnvironment: ["GIT_OPTIONAL_LOCKS": "0"]
              ), output.succeeded else { return nil }
        return output.stdout.split(whereSeparator: \.isNewline).count
    }

    /// Filter drivers (`filter.<name>.clean`, `.process`; git-lfs is one) run on files git status reads again, and
    /// a repository's config could name any program for one. Every driver the config defines is switched off for
    /// this app's git: a file under a filter may then show as changed, which only makes the row Risky. Nil when a
    /// driver's name can't be passed safely.
    private static func filtersOff(_ worktree: Worktree, git: String) async -> [String]? {
        guard let output = try? await ProcessRunner.run(
            git, gitSafety + ["-C", worktree.path, "config", "--name-only", "--get-regexp",
                              "^filter\\..+\\.(clean|smudge|process|required)$"],
            timeout: .seconds(20), extraEnvironment: ["GIT_OPTIONAL_LOCKS": "0"]
        ), output.status == 0 || output.status == 1, !output.timedOut else { return nil }  // 1: none defined
        var names = Set<String>()
        for key in output.stdout.split(whereSeparator: \.isNewline) {
            let parts = key.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { return nil }
            let name = parts.dropFirst().dropLast().joined(separator: ".")
            guard !name.contains("=") else { return nil }
            names.insert(name)
        }
        return names.sorted().flatMap { name in
            ["clean=", "smudge=", "process=", "required=false"].flatMap { ["-c", "filter.\(name).\($0)"] }
        }
    }

    /// Commits a detached worktree made that no branch, tag or remote holds: they'd be lost with it.
    static func commitsOnNoBranch(_ worktree: Worktree, git: String) async -> Int? {
        guard worktree.branch == nil else { return 0 }
        guard let output = try? await ProcessRunner.run(
            git, gitSafety + ["-C", worktree.path, "rev-list", "--count", "HEAD", "--not", "--branches", "--tags", "--remotes"],
            timeout: .seconds(60), extraEnvironment: ["GIT_OPTIONAL_LOCKS": "0"]
        ), output.succeeded else { return nil }
        return Int(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func items(repositories: [String], context: ScanContext) async -> ScanOutput {
        // Not in a file-sync folder (Dropbox, OneDrive, ...): a removal there spreads to every synced Mac. Never one
        // whose folder holds any repository the walk found (a clone kept inside it would go with it).
        let repositories = Array(Set(repositories)).sorted()
        let resolvedRepositories = repositories.compactMap(XcodeScanner.resolved)
        // Only worktrees the Trash can take (another disk: inside a scan folder there, not the scan folder itself).
        let otherDiskFolders = context.roots.filter { $0.hasPrefix("/Volumes/") }
        let worktrees = repositories.flatMap(worktrees(of:)).filter { worktree in
            [worktree.path, worktree.metadata].allSatisfy {
                Remover.isInAllowedPlace($0, scanFoldersOnOtherDisks: otherDiskFolders)
            } && ![worktree.path, worktree.metadata].contains {
                KnownLocations.isInSyncedHomeFolder($0, home: context.home) || KnownLocations.isSyncServiceData($0)
            } && !resolvedRepositories.contains { $0 == worktree.path || $0.hasPrefix(worktree.path + "/") }
        }
        guard !worktrees.isEmpty else { return ScanOutput() }
        let git = Self.git
        let recent = context.now.addingTimeInterval(-86_400)
        let items: [CleanupItem?] = await Concurrency.map(worktrees, limit: 3) { worktree -> CleanupItem? in
            // Both folders are removed only as the scan saw them: work written since, even days ago, or a commit
            // (its HEAD, index and log are in the metadata folder) keeps the worktree.
            guard let folder = FileTarget(watching: worktree.path), let metadata = FileTarget(watching: worktree.metadata) else {
                return nil
            }
            let measurement = FileSizer.measure(worktree.path, progress: context.progress)
            guard measurement.rootReadable else { return nil }
            let size = measurement.bytes
            let newest = ProjectScanner.newestChange(inWorkingCopy: worktree.path)
            // A repository of its own kept inside (outside the scan folders) would go with it: never offered.
            guard !newest.holdsClone else { return nil }
            // A submodule's own uncommitted work isn't in the worktree's status: such a copy stays unchecked.
            let changes = git == nil || newest.holdsRepository ? nil : await uncommittedChanges(worktree, git: git!)
            let looseCommits = git == nil ? nil : await commitsOnNoBranch(worktree, git: git!)
            let activity = (ProjectScanner.gitDates(worktree.path) + [newest.date].compactMap { $0 }).max()

            var facts = [PathDisplay.abbreviated(worktree.path)]
            if let activity {
                facts.append(String(localized: "changed \(activity.relativeDescription)",
                                    comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'"))
            }
            switch (changes, looseCommits) {
            case (nil, _), (_, nil):
                facts.append(git == nil
                    ? String(localized: "not checked for changes: git isn't installed",
                             comment: "Fact in a Git Worktrees row: without git the app can't see uncommitted changes")
                    : String(localized: "not checked for changes", comment: "Fact in a Git Worktrees row: git couldn't tell"))
            case (let changed?, let loose?):
                if changed > 0 {
                    facts.append(String(localized: "\(changed) files not committed",
                                        comment: "Fact in a Git Worktrees row; %lld is a number of changed files"))
                }
                if loose > 0 {
                    facts.append(String(localized: "\(loose) commits on no branch",
                                        comment: "Fact in a Git Worktrees row: commits only this detached worktree holds"))
                }
                if changed == 0, loose == 0 {
                    facts.append(String(localized: "everything committed",
                                        comment: "Fact in a Git Worktrees row: no uncommitted changes"))
                }
            }
            let clean = changes == 0 && looseCommits == 0

            // The worktree folder is checked again right before removal: nothing in it may have changed in the
            // last day (an agent may be working there).
            var worktreeTarget = folder
            worktreeTarget.projectQuietForADay = true
            worktreeTarget.gitLockFile = worktree.metadata + "/locked"
            var item = CleanupItem(
                id: worktree.path,
                category: .worktrees,
                title: (worktree.path as NSString).lastPathComponent,
                badge: worktree.branch ?? String(localized: "No branch",
                                                 comment: "Badge of a git worktree whose HEAD is detached (not on a branch)"),
                detail: facts.joined(separator: " · "),
                size: size,
                removal: .trash([worktreeTarget, metadata]),
                lockedReason: worktree.lockedInGit
                    ? String(localized: "Locked in git (git worktree lock).",
                             comment: "Why a git worktree can't be selected; keep the command as is")
                    // A tree that couldn't be read through can't be shown quiet either.
                    : activity.map { $0 > recent } == true || !newest.complete
                        ? String(localized: "Changed in the last day; a session may be running.",
                                 comment: "Why an AI agent's session history can't be selected")
                        : nil,
                date: activity,
                projectPath: worktree.repository
            )
            // Nothing uncommitted is Ask AI (its branch stays); anything that would be lost, or a state git couldn't
            // tell, is Risky.
            item.safetyLevel = clean ? .askAI : .risky
            return item
        }
        var output = ScanOutput(items: items.compactMap { $0 }.sorted { $0.size > $1.size })
        if git == nil {
            output.notes.append(String(localized: """
                Git isn't installed, so 1Cleaner can't see changes not committed in these worktrees. Install Xcode's \
                command line tools to see them.
                """, comment: "Note above the Git Worktrees list"))
        }
        return output
    }

    private static func read(_ path: String) -> String? {
        (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The worktree's `.git` file names this metadata folder (absolute or relative path).
    private static func pointsBack(_ gitFile: String, to metadata: String) -> Bool {
        guard let text = read(gitFile), text.hasPrefix("gitdir: ") else { return false }
        var target = String(text.dropFirst("gitdir: ".count))
        if !target.hasPrefix("/") { target = (gitFile as NSString).deletingLastPathComponent + "/" + target }
        guard let resolved = XcodeScanner.resolved(target) else { return false }
        return resolved == XcodeScanner.resolved(metadata)
    }
}
