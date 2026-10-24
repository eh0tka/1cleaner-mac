import Foundation
import Observation

enum SidebarDestination: Hashable {
    case overview
    case storage
    case largeFolders
    case category(CategoryID)
    case safeList
    case about
}

/// Why the Support sheet is open: the toolbar heart, or a cleanup that just finished (after
/// every successful cleanup).
enum SupportPrompt: Identifiable, Equatable {
    case manual
    case afterCleanup(freed: Int64)

    var id: String {
        switch self {
        case .manual: "manual"
        case .afterCleanup(let freed): "cleanup-\(freed)"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    let settings: SettingsStore
    let stats: StatsStore
    /// DEBUG `-demoData YES`: made-up results for website screenshots (`DemoData`).
    private(set) var isDemo = false
    let progress = ScanProgress()

    var destination: SidebarDestination? = .overview
    /// Where the person tried to go while items are checked; RootView asks first (see `navigate(to:)`).
    var pendingDestination: SidebarDestination?
    private(set) var results: [CategoryID: CategoryResult] = [:] {
        didSet { indexDuplicates() }
    }
    /// Duplicate sets by copy and by set, rebuilt with `results`: rows ask on every redraw.
    @ObservationIgnored private var duplicateGroupOf: [String: String] = [:]
    @ObservationIgnored private var duplicateMembers: [String: [String]] = [:]
    var selection: Set<String> = []
    private(set) var isScanning = false
    private(set) var hasScanned = false
    private(set) var disk: DiskSpace?
    private(set) var fullDiskAccess = false

    /// The confirmation, progress and result of one cleanup, shown as a sheet.
    var cleanup: CleanupSession?
    /// One "Move to Another Disk" in progress or just finished, shown as a sheet.
    var move: MoveSession?
    /// The latest storage breakdown of this session; the dashboard falls back to the saved summary.
    private(set) var storage: StorageReport?
    private(set) var isAnalyzingStorage = false
    let storageProgress = ScanProgress()
    private var storageTask: Task<Void, Never>?
    var isEmptyingTrash = false
    /// A short confirmation at the bottom of the window, e.g. after Copy for AI.
    var toast: String?
    var trashMessage: String?
    var support: SupportPrompt?
    private(set) var isCheckingForUpdates = false
    private(set) var updateResult: UpdateChecker.Result?
    /// Install and Relaunch is downloading, checking or swapping the app; quitting waits for it.
    private(set) var isInstallingUpdate = false
    private(set) var updateInstallError: String?
    /// The cleanup that ran last, so closing its sheet can offer support once it succeeded.
    private var lastRunCleanup: CleanupSession?

    private var scanTask: Task<Void, Never>?
    /// Category rescans running now; Stop Scan stops them too.
    private var rescanTasks: [UUID: Task<Void, Never>] = [:]

    init() {
        _ = AppLanguage.launchChoice
        #if DEBUG
        if DemoData.isOn {
            let defaults = DemoData.defaults()
            settings = SettingsStore(defaults: defaults)
            stats = StatsStore(defaults: defaults)
            stats.loadDemo(DemoData.stats())
            isDemo = true
            results = DemoData.results()
            indexDuplicates()  // property observers don't run in init
            storage = DemoData.storage()
            disk = DemoData.disk()
            hasScanned = true
            fullDiskAccess = true
            // A few rows checked by hand, as a person would before pressing Clean.
            for category in [CategoryID.projects] {
                for item in results[category]?.items.prefix(3) ?? [] { selection.insert(item.id) }
            }
            return
        }
        #endif
        settings = SettingsStore()
        stats = StatsStore()
        Task { await refreshSystemState() }
    }

    // MARK: Scan

    /// A full scan or a single-category rescan is running.
    var isBusyScanning: Bool { isScanning || results.values.contains { $0.state == .scanning } }

    /// Something to show in the lists, from a full scan or a category rescan.
    var hasResults: Bool { !results.isEmpty }

    /// The scan folders on other disks are the only places there that removal may reach.
    private func shareScanFolders() {
        let folders = settings.scanRoots.filter { $0.hasPrefix("/Volumes/") }
        Remover.scanFoldersOnOtherDisks.withLock { $0 = folders }
    }

    private func makeContext() -> ScanContext {
        // One open() call: checked at scan time so a scan started right after launch sees the real access.
        fullDiskAccess = SystemAccess.hasFullDiskAccess()
        return ScanContext(
            home: NSHomeDirectory(),
            roots: settings.scanRoots,
            progress: progress,
            now: Date(),
            fullDiskAccess: fullDiskAccess,
            safeFolders: Set(settings.safeFolders)
        )
    }

    func startScan() {
        guard !isBusyScanning, cleanup == nil, move == nil, !isDemo else { return }
        let context = makeContext()
        let started = Date()
        analyzeStorage()
        progress.reset()
        selection = []
        results = Dictionary(uniqueKeysWithValues: CategoryID.allCases.map { ($0, CategoryResult(state: .scanning)) })
        isScanning = true

        scanTask = Task {
            await withTaskGroup(of: [CategoryID: ScanOutput].self) { group in
                for scanner in ScannerCatalog.all {
                    group.addTask { await scanner.scan(context) }
                }
                for await outputs in group {
                    apply(outputs, stopped: Task.isCancelled)
                }
            }
            let stopped = Task.isCancelled
            for (id, result) in results where result.state == .scanning {
                results[id]?.state = .done
                if stopped {
                    results[id]?.notes.append(String(localized: "The scan was stopped before this category finished."))
                }
            }
            isScanning = false
            hasScanned = true
            // A stopped scan is incomplete; the dashboard keeps the last full one.
            if !stopped { stats.recordScan(started: started, results: results) }
            await refreshSystemState()
        }
    }

    func stopScan() {
        scanTask?.cancel()
        for task in rescanTasks.values { task.cancel() }
    }

    /// Scans one category again, e.g. Docker after starting it. Its scanner may fill a sibling category too
    /// (Project Builds, Large Files and Duplicates share one walk); both are refreshed. Their selection is cleared, since
    /// the items may have changed. The dashboard's last full scan is not replaced.
    func rescan(_ category: CategoryID) {
        guard !isScanning, cleanup?.phase != .running, move == nil, result(category).state != .scanning, !isDemo else { return }
        let scanners = ScannerCatalog.all.filter { $0.categories.contains(category) }
        let categories = Set(scanners.flatMap(\.categories))
        guard !categories.contains(where: { result($0).state == .scanning }) else { return }
        let context = makeContext()
        if categories.contains(.projects) { progress.reset() }
        for id in categories {
            for item in result(id).items { selection.remove(item.id) }
            results[id] = CategoryResult(state: .scanning)
        }
        // Categories nobody scanned yet show as not scanned rather than empty.
        for id in CategoryID.allCases where results[id] == nil { results[id] = CategoryResult(state: .idle) }
        let token = UUID()
        rescanTasks[token] = Task {
            await withTaskGroup(of: [CategoryID: ScanOutput].self) { group in
                for scanner in scanners {
                    group.addTask { await scanner.scan(context) }
                }
                for await outputs in group {
                    apply(outputs, stopped: Task.isCancelled)
                }
            }
            let stopped = Task.isCancelled
            for id in categories where results[id]?.state == .scanning {
                results[id]?.state = .done
                if stopped {
                    results[id]?.notes.append(String(localized: "The scan was stopped before this category finished."))
                }
            }
            rescanTasks[token] = nil
            await refreshSystemState()
        }
    }

    private func apply(_ outputs: [CategoryID: ScanOutput], stopped: Bool) {
        for (id, output) in outputs {
            let items = output.items.filter {
                !settings.isSafe($0) && !$0.removal.paths.contains(where: KnownLocations.isSyncServiceData)
            }
            var notes = output.notes
            if stopped { notes.append(String(localized: "The scan was stopped; this list may be incomplete.")) }
            // Nothing is selected for the person: every item is chosen by hand.
            results[id] = CategoryResult(state: .done, items: items, notes: notes, summary: output.summary)
        }
        removeLoneCopies()
    }

    func refreshSystemState() async {
        guard !isDemo else { return }
        let state = await Task.detached { (DiskSpace.current(), SystemAccess.hasFullDiskAccess()) }.value
        disk = state.0
        fullDiskAccess = state.1
    }

    // MARK: Navigation

    /// Every screen change by the person: with items checked, leaving asks first — clean them,
    /// clear the selection, or stay — so items ticked on one screen are never removed unnoticed from another.
    func navigate(to target: SidebarDestination?) {
        guard target != destination else { return }
        if selectedItems.isEmpty { destination = target } else { pendingDestination = target }
    }

    func clearSelection(andGoTo target: SidebarDestination?) {
        selection = []
        pendingDestination = nil
        destination = target
    }

    // MARK: Results and selection

    func result(_ category: CategoryID) -> CategoryResult {
        results[category] ?? CategoryResult()
    }

    func size(of group: CleanerGroup) -> Int64 {
        group.categories.reduce(0) { $0 + result($1).totalSize }
    }

    func selectedSize(in categories: [CategoryID]) -> Int64 {
        categories.flatMap { result($0).items }.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var selectedItems: [CleanupItem] {
        var seen = Set<String>()
        // Duplicates first: a large file is in Large Files too, and the Duplicates row carries the content check.
        let order = [CategoryID.duplicates] + CategoryID.allCases.filter { $0 != .duplicates }
        return order.flatMap { result($0).items }
            .filter { selection.contains($0.id) && $0.isSelectable && seen.insert($0.id).inserted }
    }

    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func isSelected(_ item: CleanupItem) -> Bool { selection.contains(item.id) }

    private func indexDuplicates() {
        var groupOf: [String: String] = [:]
        var members: [String: [String]] = [:]
        for item in results[.duplicates]?.items ?? [] {
            guard let group = item.duplicateGroup else { continue }
            groupOf[item.id] = group
            members[group, default: []].append(item.id)
        }
        duplicateGroupOf = groupOf
        duplicateMembers = members
    }

    /// The duplicate set of a file, also when it's checked in another list: a large file is in Large Files too.
    private func duplicateGroup(of item: CleanupItem) -> String? {
        item.duplicateGroup ?? duplicateGroupOf[item.id]
    }

    /// Duplicates: every other copy of this one's set is selected, so this one must stay.
    func isLastUnselectedCopy(_ item: CleanupItem) -> Bool {
        guard let group = duplicateGroup(of: item) else { return false }
        return (duplicateMembers[group] ?? []).filter { $0 != item.id }.allSatisfy { selection.contains($0) }
    }

    func setSelected(_ item: CleanupItem, _ selected: Bool) {
        guard item.isSelectable else { return }
        // Duplicates: one copy of each set always stays.
        if selected, let group = duplicateGroup(of: item),
           (duplicateMembers[group] ?? []).allSatisfy({ $0 == item.id || selection.contains($0) }) {
            return
        }
        if selected { selection.insert(item.id) } else { selection.remove(item.id) }
    }

    /// Select All / Select None act only on the items the list shows (after size filter and search).
    func setAll(_ items: [CleanupItem], selected: Bool) {
        guard selected else {
            for item in items where item.isSelectable { selection.remove(item.id) }
            return
        }
        // The same rule as `setSelected`, with the sets counted once so a long Duplicates list stays instant.
        let duplicates = result(.duplicates).items
        var groupOf: [String: String] = [:]
        var unselected: [String: Int] = [:]
        for copy in duplicates {
            guard let group = copy.duplicateGroup else { continue }
            groupOf[copy.id] = group
            if !selection.contains(copy.id) { unselected[group, default: 0] += 1 }
        }
        let oldest = Set(duplicates.filter(\.isOldestCopy).map(\.id))
        // Oldest copies last, so Select All in Duplicates leaves the oldest copy of each set.
        for item in items.sorted(by: { !oldest.contains($0.id) && oldest.contains($1.id) })
        where item.isSelectable && !selection.contains(item.id) {
            if let group = groupOf[item.id] {
                guard unselected[group, default: 0] > 1 else { continue }
                unselected[group, default: 0] -= 1
            }
            selection.insert(item.id)
        }
    }

    // MARK: Copy for AI

    func copyForAI(_ item: CleanupItem) {
        Task {
            let prompt = await AIPrompt.make(for: item)
            AIPrompt.copy(prompt)
            showToast(String(localized: "Copied. Paste it into Claude, Codex or ChatGPT."))
        }
    }

    func copyListForAI(_ items: [CleanupItem], category: CategoryID) {
        AIPrompt.copy(AIPrompt.makeBatch(for: items, category: category))
        let copied = min(items.count, AIPrompt.batchLimit)
        showToast(String(localized: "Copied \(copied) items. Paste them into Claude, Codex or ChatGPT."))
    }

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == text { toast = nil }
        }
    }

    // MARK: Safe List

    func addToSafeList(_ item: CleanupItem) {
        settings.addSafeItem(item)
        removeSafeItemsFromResults()
        showToast(String(localized: "“\(item.title)” is on the Safe List."))
    }

    /// Takes an item off the Safe List; when its category was scanned, scans it again so the item shows up.
    func removeFromSafeList(_ id: String) {
        let category = settings.safeItemInfo[id]?.categoryID
        settings.removeSafeItem(id)
        if let category, result(category).state == .done { rescan(category) }
    }

    func addProjectToSafeList(_ item: CleanupItem) {
        guard let project = item.projectPath else { return }
        settings.addSafeFolder(project)
        removeSafeItemsFromResults()
    }

    /// Applies Safe List changes to the current scan without scanning again.
    func removeSafeItemsFromResults() {
        for (id, result) in results {
            let removed = result.items.filter { settings.isSafe($0) }
            guard !removed.isEmpty else { continue }
            results[id]?.items.removeAll { settings.isSafe($0) }
            for item in removed { selection.remove(item.id) }
        }
        removeLoneCopies()
    }

    // MARK: Cleanup

    func prepareCleanup() {
        var items = selectedItems.sorted { ($0.removal.order, -$0.size) < ($1.removal.order, -$1.size) }
        // The duplicates rule, whichever lists the copies were checked in and with checked folders (an old download)
        // taking the copies inside them: when every copy of a set would go, the oldest copy's own row, or else the
        // row whose folder holds it, stays out of the cleanup. Memory only; the disk is checked per item at removal.
        // Only when a copy is checked by its own row: folders checked for themselves go as chosen.
        var index = SelectionIndex(items)
        for copies in Dictionary(grouping: result(.duplicates).items, by: { $0.duplicateGroup ?? "" }).values
        where copies.contains(where: { index.ids.contains($0.id) }) && !copies.contains(where: { index.covering($0) == nil }) {
            let keep = copies.first(where: \.isOldestCopy) ?? copies[0]
            // Its own row and a checked folder holding it may both be selected: neither may take it.
            while let covering = index.covering(keep) {
                items.removeAll { $0.id == covering.id }
                index = SelectionIndex(items)
            }
        }
        guard !items.isEmpty, !isBusyScanning else { return }
        shareScanFolders()
        cleanup = CleanupSession(items: items)
    }

    func startCleanup() {
        guard let session = cleanup, session.phase == .confirming else { return }
        #if DEBUG
        if isDemo {
            // The demo uses the real result sheet, but never calls a remover, scans disk or empties Trash.
            session.freeBefore = disk?.available
            for item in session.items {
                session.record(item, item.removal.isPermanent ? .removed : .movedToTrash)
                selection.remove(item.id)
                removeFromResults(item)
            }
            // Files moved to Trash still occupy space. Only tool removals reclaim it immediately.
            session.freeAfter = session.freeBefore.map { $0 + session.removedByTools }
            session.phase = .finished
            return
        }
        #endif
        guard !isDemo else { return }
        session.phase = .running
        lastRunCleanup = session
        session.task = Task {
            session.freeBefore = disk?.available
            var removedPaths: [String] = []
            for (index, item) in session.items.enumerated() {
                // Stop finishes the current item: a tool interrupted mid-way could leave a half-removed image.
                if session.stopRequested { break }
                // Inside a folder this cleanup already moved (an installer in an old download): gone with it.
                if !item.removal.paths.isEmpty, item.removal.paths.allSatisfy({ path in
                    removedPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
                }) {
                    selection.remove(item.id)
                    continue
                }
                session.current = item.title
                let outcome: Remover.Outcome
                if await duplicateWouldBeLost(removing: item, remaining: session.items[index...]) {
                    outcome = .failed(String(localized: "It changed since the scan. Scan again.",
                                             comment: "Why an item can't be moved to the Trash"))
                } else {
                    outcome = await Remover.remove(item)
                }
                session.record(item, outcome)
                switch outcome {
                case .movedToTrash, .removed:
                    selection.remove(item.id)
                    removedPaths += item.removal.paths
                    removeFromResults(item)
                case .failed:
                    break
                }
            }
            session.stopped = session.stopRequested
            stats.recordCleanup(
                movedToTrash: session.movedToTrash,
                removedByTools: session.removedByTools,
                items: session.processed - session.failures.count
            )
            await refreshSystemState()
            session.freeAfter = disk?.available
            session.phase = .finished
            refreshTrash()
            // Images become unused only once their stopped containers are gone; list them right away.
            if session.removedContainers { rescan(.docker) }
        }
    }

    /// A removed path leaves every list it was in (a large file is also a duplicate), and a duplicate set with one
    /// copy left is no longer a set.
    private func removeFromResults(_ removed: CleanupItem) {
        // Rows inside a removed folder are gone with it (a duplicate in an old download folder).
        let paths = removed.removal.paths
        // A row with other parts left (an app whose cache was cleaned) stays; its removal skips the moved part.
        func gone(_ item: CleanupItem) -> Bool {
            item.id == removed.id || !item.removal.paths.isEmpty && item.removal.paths.allSatisfy { path in
                paths.contains { path == $0 || path.hasPrefix($0 + "/") }
            }
        }
        for category in results.keys {
            let removedHere = results[category]?.items.filter(gone) ?? []
            guard !removedHere.isEmpty else { continue }
            for item in removedHere { selection.remove(item.id) }
            results[category]?.items.removeAll(where: gone)
        }
        removeLoneCopies()
    }

    private func removeLoneCopies() {
        guard let items = results[.duplicates]?.items else { return }
        let counts = Dictionary(items.compactMap { $0.duplicateGroup.map { ($0, 1) } }, uniquingKeysWith: +)
        let lone = items.filter { item in item.duplicateGroup.map { counts[$0, default: 0] < 2 } ?? false }
        guard !lone.isEmpty else { return }
        for item in lone { selection.remove(item.id) }
        let ids = Set(lone.map(\.id))
        results[.duplicates]?.items.removeAll { ids.contains($0.id) }
    }

    /// The selected rows by id and by path, so finding the row that would remove a copy is a few lookups.
    private struct SelectionIndex {
        let ids: Set<String>
        private let byID: [String: CleanupItem]
        private let byPath: [String: CleanupItem]

        init<Items: Sequence>(_ items: Items) where Items.Element == CleanupItem {
            ids = Set(items.map(\.id))
            byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            byPath = Dictionary(items.flatMap { item in item.removal.paths.map { ($0, item) } }, uniquingKeysWith: { first, _ in first })
        }

        /// The selected row that would remove this copy: its own row, or a checked folder holding it.
        func covering(_ copy: CleanupItem) -> CleanupItem? {
            if let own = byID[copy.id] { return own }
            for path in copy.removal.paths {
                var folder = path
                while !folder.isEmpty, folder != "/" {
                    if let item = byPath[folder] { return item }
                    folder = (folder as NSString).deletingLastPathComponent
                }
            }
            return nil
        }
    }

    /// Right before an item goes: every duplicate set it holds a copy of still has a copy that stays, exists and is
    /// unchanged since the scan (an edited copy is no longer the same file). The disk is checked off the main thread.
    private func duplicateWouldBeLost(removing item: CleanupItem, remaining: ArraySlice<CleanupItem>) async -> Bool {
        // Only a copy removed by its own row (or the same file in Large Files): a folder goes as chosen.
        guard let group = duplicateGroupOf[item.id] else { return false }
        let copies = result(.duplicates).items
        let index = SelectionIndex(remaining)
        let keepers = copies.filter { $0.duplicateGroup == group && index.covering($0) == nil }
        let targets = keepers.compactMap { copy -> FileTarget? in
            if case .trash(let parts) = copy.removal { return parts.first }
            return nil
        }
        return !(await Remover.anyUnchanged(targets))
    }

    func stopCleanup() {
        cleanup?.stopRequested = true
    }

    func closeCleanup() {
        guard cleanup?.phase != .running else { return }
        cleanup = nil
    }

    /// Called when the cleanup sheet has closed: the very first cleanup that removed something offers support once;
    /// after that only the toolbar heart does.
    func cleanupSheetClosed() {
        guard let session = lastRunCleanup, session.phase == .finished else { return }
        lastRunCleanup = nil
        let freed = session.movedToTrash + session.removedByTools
        guard freed > 0, stats.stats.cleanups == 1 else { return }
        support = .afterCleanup(freed: freed)
    }

    // MARK: Updates

    func checkForUpdates() {
        guard !isCheckingForUpdates, !isInstallingUpdate else { return }
        isCheckingForUpdates = true
        updateResult = nil
        updateInstallError = nil
        Task {
            updateResult = await UpdateChecker.check()
            isCheckingForUpdates = false
        }
    }

    /// Not while a scan, cleanup or move runs: the new copy starts right away.
    var canInstallUpdate: Bool { !isInstallingUpdate && !isBusyScanning && cleanup == nil && move == nil && !isDemo }

    func installUpdate(_ release: UpdateChecker.Release) {
        guard canInstallUpdate else { return }
        isInstallingUpdate = true
        updateInstallError = nil
        Task {
            if let error = await Updater.install(release) {
                updateInstallError = error
                isInstallingUpdate = false
                return
            }
            // Done swapping: quitting may go on, and the new copy starts in place of this one.
            isInstallingUpdate = false
            AppLanguage.relaunch { [weak self] in
                self?.updateInstallError = String(localized: "The update is installed. Quit 1Cleaner and open it again to start the new version.",
                                                  comment: "Shown when the update is in place but macOS couldn't start the new copy")
            }
        }
    }

    // MARK: Storage breakdown

    func analyzeStorage() {
        guard !isAnalyzingStorage, !isDemo else { return }
        isAnalyzingStorage = true
        storageProgress.reset()
        let access = SystemAccess.hasFullDiskAccess()
        let progress = storageProgress
        storageTask = Task {
            let report = await StorageAnalyzer.analyze(home: NSHomeDirectory(), fullDiskAccess: access, progress: progress)
            isAnalyzingStorage = false
            guard !Task.isCancelled else { return }
            storage = report
            stats.recordStorage(report)
        }
    }

    func stopStorageAnalysis() {
        storageTask?.cancel()
    }

    // MARK: Move to another disk

    func startMove(_ item: CleanupItem, to folder: String) {
        // Not during a scan: a scan finishing after the move would list the moved item again.
        guard move == nil, cleanup == nil, !isBusyScanning, item.canMoveToAnotherDisk else { return }
        shareScanFolders()
        let session = MoveSession(item: item, destination: folder)
        move = session
        session.task = Task {
            let outcome = await Mover.move(item, to: folder) { copied, total in
                Task { @MainActor in
                    session.copied = copied
                    session.total = total
                }
            }
            session.outcome = outcome
            if case .moved = outcome {
                selection.remove(item.id)
                removeFromResults(item)
                stats.recordCleanup(movedToTrash: item.size, removedByTools: 0, items: 1)
            }
            await refreshSystemState()
            refreshTrash()
        }
    }

    func stopMove() {
        move?.task?.cancel()
    }

    // MARK: Quit

    /// A cleanup or a move is changing files right now.
    var isChangingFiles: Bool {
        cleanup?.phase == .running || (move != nil && move?.outcome == nil)
    }

    /// Quitting while files change: the cleanup stops after its current item, a move stops and
    /// removes its unfinished copy; then `done` runs. After a minute it runs anyway, so quitting never hangs.
    func stopForQuit(then done: @escaping @MainActor () -> Void) {
        stopCleanup()
        stopMove()
        let tasks = [cleanup?.task, move?.task].compactMap { $0 }
        let gate = QuitGate(done)
        Task { for task in tasks { await task.value }; gate.finish() }
        Task { try? await Task.sleep(for: .seconds(60)); gate.finish() }
    }

    func closeMove() {
        guard move?.outcome != nil else { return }
        move = nil
    }

    // MARK: Trash

    func emptyTrash() {
        // Demo data stands for a made-up Mac: never empty the real Trash behind it.
        guard !isEmptyingTrash, !isDemo else { return }
        isEmptyingTrash = true
        Task {
            let failure = await SystemAccess.emptyTrash()
            isEmptyingTrash = false
            trashMessage = failure
            await refreshSystemState()
            if let session = cleanup, session.phase == .finished, failure == nil {
                session.trashEmptied = true
                session.freeAfter = disk?.available
            }
            refreshTrash()
        }
    }

    private func refreshTrash() {
        guard hasScanned else { return }
        let context = ScanContext(home: NSHomeDirectory(), roots: [], progress: ScanProgress(), now: Date(),
                                  fullDiskAccess: fullDiskAccess)
        Task {
            let outputs = await TrashScanner().scan(context)
            if let output = outputs[.trash] {
                results[.trash] = CategoryResult(state: .done, items: output.items, notes: output.notes)
            }
        }
    }
}

/// Runs `done` once: whichever comes first, the work stopping or the time limit.
@MainActor
private final class QuitGate {
    private var done: (@MainActor () -> Void)?

    init(_ done: @escaping @MainActor () -> Void) { self.done = done }

    func finish() {
        done?()
        done = nil
    }
}

@MainActor
@Observable
final class CleanupSession {
    enum Phase { case confirming, running, finished }

    struct Failure: Identifiable {
        let id = UUID()
        let title: String
        let reason: String
    }

    let items: [CleanupItem]
    var phase: Phase = .confirming
    var current = ""
    var processed = 0
    var movedToTrash: Int64 = 0
    var removedByTools: Int64 = 0
    var failures: [Failure] = []
    var stopRequested = false
    var stopped = false
    var trashEmptied = false
    var freeBefore: Int64?
    var freeAfter: Int64?
    @ObservationIgnored var task: Task<Void, Never>?

    init(items: [CleanupItem]) {
        self.items = items
    }

    var trashItems: [CleanupItem] { items.filter { !$0.removal.isPermanent } }
    var permanentItems: [CleanupItem] { items.filter { $0.removal.isPermanent } }

    /// Stopped containers removed together with their selected images, not selected on their own.
    var extraContainers: Int {
        let selected = Set(items.compactMap { item -> String? in
            if case .docker(.container(let id)) = item.removal { return id }
            return nil
        })
        let implied = items.flatMap { item -> [String] in
            if case .docker(.image(_, let containers, _)) = item.removal { return containers }
            return []
        }
        return Set(implied).subtracting(selected).count
    }

    var removedContainers = false

    func record(_ item: CleanupItem, _ outcome: Remover.Outcome) {
        processed += 1
        switch outcome {
        case .movedToTrash: movedToTrash += item.size
        case .removed:
            removedByTools += item.size
            switch item.removal {
            case .docker(.container): removedContainers = true
            case .docker(.image(_, let containers, _)) where !containers.isEmpty: removedContainers = true
            default: break
            }
        case .failed(let reason): failures.append(Failure(title: item.title, reason: reason))
        }
    }
}

@MainActor
@Observable
final class MoveSession: Identifiable {
    let item: CleanupItem
    let destination: String
    var copied: Int64 = 0
    var total: Int64 = 0
    var outcome: Mover.Outcome?
    @ObservationIgnored var task: Task<Void, Never>?

    init(item: CleanupItem, destination: String) {
        self.item = item
        self.destination = destination
    }

    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
