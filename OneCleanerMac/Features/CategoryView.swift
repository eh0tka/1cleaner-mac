import AppKit
import SwiftUI

/// Quick size filter next to the search field; hides small entries so the list shows what matters.
enum SizeFilter: Int, CaseIterable, Identifiable {
    case all = 0
    case tenMB = 10
    case hundredMB = 100
    case oneGB = 1000

    var id: Int { rawValue }
    var minimumBytes: Int64 { Int64(rawValue) * 1_000_000 }

    var title: String {
        switch self {
        case .all: String(localized: "All", comment: "Size filter: show items of any size")
        case .tenMB: String(localized: "10 MB+", comment: "Size filter: items of 10 MB or larger")
        case .hundredMB: String(localized: "100 MB+", comment: "Size filter: items of 100 MB or larger")
        case .oneGB: String(localized: "1 GB+", comment: "Size filter: items of 1 GB or larger")
        }
    }
}

struct CategoryView: View {
    @Environment(AppModel.self) private var model
    let category: CategoryID
    @State private var search = ""
    @State private var confirmEmptyTrash = false
    /// Shared by all lists and remembered between launches.
    @AppStorage("sizeFilter") private var sizeFilter: SizeFilter = .tenMB

    var body: some View {
        let result = model.result(category)
        let items = filtered(result.items)
        let hiddenBySize = category == .trash ? 0
            : result.items.filter { $0.size < sizeFilter.minimumBytes && matchesSearch($0) }.count
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header(result, visible: items)
                if category == .simulators {
                    SimulatorLegend()
                } else {
                    Text(category.explanation)
                        .font(.app(13))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if category != .trash {
                    HStack(alignment: .top, spacing: 14) {
                        SafetyLegend()
                        Spacer()
                        let askAI = items.filter { $0.safety == .askAI }
                        if !askAI.isEmpty {
                            Button {
                                model.copyListForAI(askAI, category: category)
                            } label: {
                                Label("Ask AI about \(askAI.count) items", systemImage: "sparkles")
                                    .font(.app(12, weight: .semibold))
                            }
                            .buttonStyle(.link)
                            .help("Copies one question about every Ask AI row shown, answered as a table: remove, keep or check.")
                        }
                    }
                }
                if category == .docker || category == .simulators {
                    NoteBanner(text: category == .docker
                        ? String(localized: """
                            These items don't go to the Trash: Docker removes them for good. You'll confirm them \
                            separately. A volume can hold a database: select one only if you're sure.
                            """)
                        : String(localized: """
                            These items don't go to the Trash: Xcode removes them for good. You'll confirm them \
                            separately.
                            """),
                        tone: .danger)
                }
                if let summary = result.summary {
                    NoteBanner(text: summary)
                }
                ForEach(result.notes, id: \.self) { note in
                    NoteBanner(text: note, tone: .warning)
                }
                if result.state == .done, hiddenBySize > 0 {
                    HStack(spacing: 8) {
                        Text("\(hiddenBySize) items under \(sizeFilter.minimumBytes.formattedBytes) hidden")
                            .font(.app(12))
                            .foregroundStyle(Theme.secondaryText)
                        Button("Show All") { sizeFilter = .all }
                            .buttonStyle(.link)
                            .font(.app(12, weight: .semibold))
                    }
                }
                content(result, items: items)
            }
            .padding(28)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(category.title)
        .searchable(text: $search, placement: .toolbar, prompt: "Filter")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Size", selection: $sizeFilter) {
                    ForEach(SizeFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Show only items of this size or larger")
            }
        }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmptyTrash) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
                Everything in the Trash is deleted for good, including files you put there yourself. \
                This can't be undone.
                """)
        }
    }

    @ViewBuilder
    private func header(_ result: CategoryResult, visible: [CleanupItem]) -> some View {
        HStack(spacing: 14) {
            Image(systemName: category.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title).font(.app(24, weight: .bold))
                if result.state == .done {
                    Text("\(result.totalSize.formattedBytes) found · \(model.selectedSize(in: [category]).formattedBytes) selected")
                        .font(.app(12.5))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            if result.state == .done {
                Button {
                    model.rescan(category)
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isScanning || model.cleanup != nil)
                .help(rescanHelp)
            }
            if category != .trash, visible.contains(where: \.isSelectable) {
                Button("Select All") { model.setAll(visible, selected: true) }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("Selects the items shown in the list")
                Button("Select None") { model.setAll(visible, selected: false) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func content(_ result: CategoryResult, items: [CleanupItem]) -> some View {
        switch result.state {
        case .idle:
            Panel(padding: 24) {
                HStack(spacing: 10) {
                    Text("Scan to see what's here.").font(.app(14)).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button("Scan Everything") { model.startScan() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.isBusyScanning || model.cleanup != nil)
                    Button("Scan \(category.title)") { model.rescan(category) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.isScanning || model.cleanup != nil)
                }
            }
        case .scanning:
            Panel(padding: 24) {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Scanning…").font(.app(14)).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button("Stop") { model.stopScan() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        case .done where category == .trash:
            trashPanel(result)
        case .done where category == .duplicates && !items.isEmpty:
            DuplicateGroupsList(all: result.items, visible: items)
        case .done where category == .worktrees && !items.isEmpty:
            RepositoryGroupsList(items: items)
        case .done where items.isEmpty:
            Panel(padding: 24) {
                Label(result.items.isEmpty
                        ? String(localized: "Nothing to clean here.") : String(localized: "Nothing matches the filter."),
                      systemImage: "checkmark.circle.fill")
                    .font(.app(14, weight: .medium))
                    .foregroundStyle(Theme.success)
            }
        case .done:
            VStack(spacing: 0) {
                ForEach(items) { item in
                    ItemRow(item: item)
                    if item.id != items.last?.id { Divider().padding(.leading, 44) }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
        }
    }

    private func trashPanel(_ result: CategoryResult) -> some View {
        let item = result.items.first
        return Panel(padding: 24) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    let trash = String(localized: "Trash")
                    Text(item.map { $0.size > 0 ? $0.size.formattedBytes : trash } ?? trash)
                        .font(.appNumber(28))
                    Text(item?.detail ?? "")
                        .font(.app(12.5))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if model.isEmptyingTrash {
                    ProgressView().controlSize(.small)
                }
                Button("Empty Trash…") { confirmEmptyTrash = true }
                    .buttonStyle(PrimaryButtonStyle(destructive: true))
                    .disabled(model.isEmptyingTrash)
            }
        }
    }

    private var rescanHelp: String {
        switch category {
        case .projects, .worktrees, .largeFiles, .duplicates:
            String(localized: """
                Scans the scan folders again; Project Builds, Git Worktrees, Large Files and Duplicates refresh together
                """)
        default: String(localized: "Scans only \(category.title) again")
        }
    }

    private func filtered(_ items: [CleanupItem]) -> [CleanupItem] {
        let minimum = category == .trash ? 0 : sizeFilter.minimumBytes
        return items.filter { $0.size >= minimum && matchesSearch($0) }
    }

    private func matchesSearch(_ item: CleanupItem) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return item.title.localizedCaseInsensitiveContains(query) || item.detail.localizedCaseInsensitiveContains(query)
            || (item.badge?.localizedCaseInsensitiveContains(query) ?? false)
    }
}

private struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: CleanupItem

    var body: some View {
        let selected = model.isSelected(item)
        HStack(spacing: 12) {
            if let locked = item.lockedReason {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 20)
                    .help(locked)
            } else {
                let lastCopy = !selected && model.isLastUnselectedCopy(item)
                Toggle("", isOn: Binding(
                    get: { selected },
                    set: { model.setSelected(item, $0) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 20)
                .disabled(lastCopy)
                .help(lastCopy ? String(localized: "One copy always stays.", comment: "Tooltip of a disabled Duplicates checkbox") : "")
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.app(13.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let badge = item.badge {
                        Text(badge)
                            .font(.app(10.5, weight: .semibold))
                            .foregroundStyle(Theme.accentDeep)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accentSoft, in: Capsule())
                    }
                }
                Text(item.lockedReason ?? item.detail)
                    .font(.app(11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if item.removal != .emptyTrash { SafetyBadge(item: item) }
            Text(item.size.formattedBytes)
                .font(.appNumber(13.5, weight: .semibold))
                .foregroundStyle(selected ? Theme.accentDeep : Theme.text)
                .monospacedDigit()
            if let path = item.revealPath {
                Button {
                    SystemAccess.reveal(path)
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Safe List and more")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { model.setSelected(item, !selected) }
        .contextMenu { menuItems }
        .help(item.removal.paths.count > 1
            ? item.removal.paths.map(PathDisplay.abbreviated).joined(separator: "\n") : "")
    }

    private func chooseDiskAndMove() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Move Here")
        panel.message = String(localized: """
            Choose a folder on another disk. 1Cleaner copies “\(item.title)” there, checks the copy, \
            then moves the original to the Trash.
            """)
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        if panel.runModal() == .OK, let url = panel.url {
            model.startMove(item, to: url.path)
        }
    }

    /// Same actions in the row's ••• menu and its right-click menu.
    @ViewBuilder
    private var menuItems: some View {
        if let path = item.revealPath {
            Button("Show in Finder") { SystemAccess.reveal(path) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
            Divider()
        }
        if item.canMoveToAnotherDisk {
            Button("Move to Another Disk…") { chooseDiskAndMove() }
                .disabled(model.move != nil || model.cleanup != nil || model.isBusyScanning)
            Divider()
        }
        Button("Copy for AI") { model.copyForAI(item) }
        Button("Add to Safe List") { model.addToSafeList(item) }
        if let project = item.projectPath {
            Button("Add Project “\((project as NSString).lastPathComponent)” to Safe List") {
                model.addProjectToSafeList(item)
            }
        }
    }
}

/// Git Worktrees, one group per repository, open from the start: each worktree is its own choice.
private struct RepositoryGroupsList: View {
    let items: [CleanupItem]

    private var groups: [[CleanupItem]] {
        let byRepository: [String: [CleanupItem]] = Dictionary(grouping: items, by: { $0.projectPath ?? "" })
        let sorted: [[CleanupItem]] = byRepository.values.map { list in list.sorted { $0.size > $1.size } }
        return sorted.sorted { Self.total($0) > Self.total($1) }
    }

    static func total(_ worktrees: [CleanupItem]) -> Int64 {
        worktrees.reduce(Int64(0)) { $0 + $1.size }
    }

    var body: some View {
        let groups = groups
        VStack(spacing: 0) {
            ForEach(groups, id: \.first?.projectPath) { worktrees in
                RepositoryGroupRow(worktrees: worktrees)
                if worktrees.first?.projectPath != groups.last?.first?.projectPath { Divider().padding(.leading, 44) }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }
}

private struct RepositoryGroupRow: View {
    @Environment(AppModel.self) private var model
    let worktrees: [CleanupItem]
    @State private var expanded = true

    var body: some View {
        let repository = worktrees.first?.projectPath ?? ""
        let selected = worktrees.contains { model.isSelected($0) }
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: (repository as NSString).lastPathComponent)
                            .font(.app(13.5, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(verbatim: String(localized: "\(worktrees.count) worktrees",
                                              comment: "Git Worktrees group: how many worktrees one repository has")
                             + " · " + PathDisplay.abbreviated(repository))
                            .font(.app(11.5))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 12)
                    Text(RepositoryGroupsList.total(worktrees).formattedBytes)
                        .font(.appNumber(13.5, weight: .semibold))
                        .foregroundStyle(selected ? Theme.accentDeep : Theme.text)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(worktrees) { worktree in
                    Divider().padding(.leading, 76)
                    ItemRow(item: worktree).padding(.leading, 32)
                }
            }
        }
    }
}

/// Safe / Ask AI / Risky on a row. Ask AI copies a description of the item for an AI assistant.
/// Duplicates as one row per file: the row shows how many copies there are and where; opening
/// it lists every copy to choose from. One copy always stays.
private struct DuplicateGroupsList: View {
    /// Every copy in the category, so a set shows whole even when the filter matches one copy.
    let all: [CleanupItem]
    let visible: [CleanupItem]

    var body: some View {
        let shown = Set(visible.compactMap(\.duplicateGroup))
        let groups = Dictionary(grouping: all.filter { $0.duplicateGroup.map(shown.contains) ?? false },
                                by: { $0.duplicateGroup ?? "" })
            .values
            .filter { $0.count > 1 }
            .map { $0.sorted { ($0.isOldestCopy ? 0 : 1, $0.date ?? .distantFuture) < ($1.isOldestCopy ? 0 : 1, $1.date ?? .distantFuture) } }
            .sorted { Self.freeable($0) > Self.freeable($1) }
        VStack(spacing: 0) {
            ForEach(groups, id: \.first?.duplicateGroup) { copies in
                DuplicateGroupRow(copies: copies)
                if copies.first?.duplicateGroup != groups.last?.first?.duplicateGroup { Divider().padding(.leading, 44) }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }

    /// Space freed by removing every copy but one.
    static func freeable(_ copies: [CleanupItem]) -> Int64 {
        copies.reduce(0) { $0 + $1.size } - (copies.map(\.size).max() ?? 0)
    }
}

private struct DuplicateGroupRow: View {
    @Environment(AppModel.self) private var model
    let copies: [CleanupItem]
    @State private var expanded = Self.expandedAtStart

    /// `-expandDuplicates YES` (debug): every set open, for snapshots.
    private static var expandedAtStart: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "expandDuplicates")
        #else
        return false
        #endif
    }

    var body: some View {
        let selected = copies.filter { model.isSelected($0) }.count
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: ((copies.first?.revealPath ?? "") as NSString).lastPathComponent)
                            .font(.app(13.5, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(verbatim: String(localized: "\(copies.count) copies",
                                              comment: "Duplicates row: how many copies of one file were found")
                             + " · " + folders)
                            .font(.app(11.5))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 12)
                    Text(DuplicateGroupsList.freeable(copies).formattedBytes)
                        .font(.appNumber(13.5, weight: .semibold))
                        .foregroundStyle(selected > 0 ? Theme.accentDeep : Theme.text)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(copies) { copy in
                    Divider().padding(.leading, 76)
                    ItemRow(item: copy).padding(.leading, 32)
                }
            }
        }
    }

    /// The folders holding the copies, e.g. "~/Downloads, ~/Documents/Taxes".
    private var folders: String {
        var seen = Set<String>()
        return copies.compactMap { $0.revealPath.map { PathDisplay.abbreviated(($0 as NSString).deletingLastPathComponent) } }
            .filter { seen.insert($0).inserted }
            .joined(separator: ", ")
    }
}

private struct SafetyBadge: View {
    @Environment(AppModel.self) private var model
    let item: CleanupItem

    var body: some View {
        let level = item.safety
        let label = Label(level.title, systemImage: level.systemImage)
            .font(.app(10.5, weight: .semibold))
            .foregroundStyle(level.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(level.color.opacity(0.1), in: Capsule())
        if level == .askAI {
            Button { model.copyForAI(item) } label: { label }
                .buttonStyle(.plain)
                .help(level.help)
        } else {
            label.help(level.help)
        }
    }
}

/// Device versus Runtime, the difference that decides what removing a simulator costs.
/// What the row labels mean (people read "Risky" as "the app is risky"): each label says how safe
/// deleting is, with its meaning next to it. Side by side when they fit, otherwise one per line.
private struct SafetyLegend: View {
    private let levels: [Safety] = [.safe, .askAI, .risky]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Labels show how safe it is to delete each item. Nothing is selected for you.")
                .font(.app(11.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { entries }
                VStack(alignment: .leading, spacing: 4) { entries }
            }
        }
    }

    private var entries: some View {
        ForEach(levels, id: \.self) { level in
            HStack(spacing: 5) {
                Label(level.title, systemImage: level.systemImage)
                    .font(.app(11.5, weight: .semibold))
                    .foregroundStyle(level.color)
                Text(level.meaning)
                    .font(.app(11.5))
                    .foregroundStyle(Theme.secondaryText)
            }
            .fixedSize()
            .help(level.help)
        }
    }
}

private struct SimulatorLegend: View {
    var body: some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                row("iphone", "Device", """
                    One virtual iPhone or iPad with its apps and data. Removing it keeps its iOS; a new one is created \
                    in seconds (agents and Xcode do it themselves).
                    """)
                row("square.stack.3d.down.right", "Runtime", """
                    An iOS version itself, shared by its devices. Removing it stops those devices until you download \
                    that iOS again (several GB).
                    """)
                Text("Xcode removes both for good, they don't go to the Trash. Running simulators can't be removed.")
                    .font(.app(12))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            ((Text(title) + Text(verbatim: " — ")).font(.app(13, weight: .semibold)) + Text(text).font(.app(13)))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
