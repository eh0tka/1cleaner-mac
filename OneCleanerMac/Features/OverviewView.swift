import SwiftUI

/// The dashboard: what 1Cleaner has done on this Mac, the disk, the last scan and the way into a new one.
struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.stats.stats
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                // Near the top: the permission matters for what the scan can see.
                if !model.fullDiskAccess { fullDiskAccessBanner }
                HStack(alignment: .top, spacing: 16) {
                    CleanedTile(stats: stats)
                    LastScanTile(stats: stats)
                    DiskTile(disk: model.disk)
                }
                .fixedSize(horizontal: false, vertical: true)
                StoragePanel()
                if model.isScanning { ScanProgressPanel() }
                HStack(alignment: .top, spacing: 16) {
                    ForEach(CleanerGroup.allCases, id: \.self) { group in
                        GroupCard(group: group)
                    }
                }
                if !stats.history.isEmpty { HistoryPanel(history: stats.history) }
            }
            .padding(28)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Dashboard")
    }

    private var header: some View {
        HStack(spacing: 16) {
            BrandMark(size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("1Cleaner")
                    .font(.app(26, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Caches, leftovers, big files and developer junk. Nothing is removed until you confirm.")
                    .font(.app(13))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if model.isScanning {
                Button("Stop") { model.stopScan() }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                Button {
                    model.startScan()
                } label: {
                    Label(model.hasScanned ? String(localized: "Scan Again") : String(localized: "Scan"),
                          systemImage: "magnifyingglass")
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(model.cleanup != nil || model.isBusyScanning)
            }
        }
    }

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 12) {
            NoteBanner(text: String(localized: """
                Optional: Full Disk Access lets 1Cleaner include Safari's cache, the Trash size and a \
                few protected caches. Everything else works without it.
                """))
            Button("Open Settings") { SystemAccess.openFullDiskAccessSettings() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }
}

// MARK: Tiles

private struct Tile<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        Panel(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.app(12, weight: .semibold))
                    .foregroundStyle(Theme.accentDeep)
                content
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct CleanedTile: View {
    let stats: StatsStore.Stats

    var body: some View {
        Tile(title: "Cleaned with 1Cleaner", systemImage: "sparkles") {
            Text(stats.cleanedBytes.formattedBytes)
                .font(.appNumber(30))
                .foregroundStyle(Theme.text)
            (stats.cleanups == 0
                ? Text("Your first cleanup will show up here.")
                : Text("""
                    \(stats.cleanups) cleanups · \(stats.itemsRemoved) items since \
                    \(stats.firstUse.formatted(date: .abbreviated, time: .omitted))
                    """))
                .font(.app(12))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct LastScanTile: View {
    @Environment(AppModel.self) private var model
    let stats: StatsStore.Stats

    var body: some View {
        Tile(title: "Last scan", systemImage: "clock.arrow.circlepath") {
            if let scan = stats.lastScan {
                Text(scan.found.formattedBytes)
                    .font(.appNumber(30))
                    .foregroundStyle(Theme.text)
                Text("found \(scan.date.relativeDescription) · took \(scan.seconds) s")
                    .font(.app(12))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Not yet")
                    .font(.appNumber(30))
                    .foregroundStyle(Theme.secondaryText)
                Text("A scan only reads. You choose what goes to the Trash.")
                    .font(.app(12))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

private struct DiskTile: View {
    let disk: DiskSpace?

    var body: some View {
        Tile(title: "Macintosh HD", systemImage: "internaldrive") {
            if let disk {
                Text(disk.available.formattedBytes)
                    .font(.appNumber(30))
                    .foregroundStyle(freeColor(disk))
                Text("available of \(disk.total.formattedBytes)")
                    .font(.app(12))
                    .foregroundStyle(Theme.secondaryText)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.hairline)
                        Capsule()
                            .fill(Theme.accentGradient)
                            .frame(width: proxy.size.width * CGFloat(disk.used) / CGFloat(max(disk.total, 1)))
                    }
                }
                .frame(height: 8)
            } else {
                Text(verbatim: "—").font(.appNumber(30)).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// Warns when less than a tenth of the disk is free, the point where macOS and Xcode start to struggle.
    private func freeColor(_ disk: DiskSpace) -> Color {
        Double(disk.available) / Double(max(disk.total, 1)) < 0.1 ? Theme.danger : Theme.text
    }
}

// MARK: Scan progress, groups, history

private struct ScanProgressPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Panel(padding: 22) {
            HStack(spacing: 18) {
                ProgressView().controlSize(.large)
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    let snapshot = model.progress.snapshot
                    let finished = CategoryID.allCases.filter { model.result($0).state == .done }.count
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scanning… \(finished) of \(CategoryID.allCases.count) categories ready")
                            .font(.app(16, weight: .semibold))
                        (snapshot.currentFolder.isEmpty
                            ? Text("\(snapshot.entries) files checked")
                            : Text("\(snapshot.entries) files checked · \(snapshot.currentFolder)"))
                            .font(.app(12))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
            }
        }
    }
}

private struct GroupCard: View {
    @Environment(AppModel.self) private var model
    let group: CleanerGroup

    var body: some View {
        let lastScan = model.stats.stats.lastScan
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: group == .developer ? "hammer.fill" : "house.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        (group == .developer ? Text("Developer Cleaner") : Text("Everyday Cleaner"))
                            .font(.app(16, weight: .bold))
                        if model.hasScanned || model.isScanning {
                            Text("\(model.size(of: group).formattedBytes) found")
                                .font(.app(12))
                                .foregroundStyle(Theme.secondaryText)
                        } else if let lastScan {
                            let total = group.categories.reduce(0) { $0 + lastScan.size(of: $1) }
                            Text("\(total.formattedBytes) at the last scan, \(lastScan.date.relativeDescription)")
                                .font(.app(12))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Spacer()
                }
                VStack(spacing: 2) {
                    ForEach(group.categories) { category in
                        CategoryLine(category: category)
                    }
                }
            }
        }
    }
}

private struct CategoryLine: View {
    @Environment(AppModel.self) private var model
    let category: CategoryID

    var body: some View {
        let result = model.result(category)
        let lastScanSize = model.stats.stats.lastScan?.size(of: category)
        Button {
            model.navigate(to: .category(category))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: category.systemImage)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20)
                Text(category.title)
                    .font(.app(13))
                    .foregroundStyle(Theme.text)
                Spacer()
                switch result.state {
                case .idle:
                    // Before this session's scan: last scan's size, dimmed, as a hint where the space is.
                    if let lastScanSize, lastScanSize > 0 {
                        Text(lastScanSize.formattedBytes)
                            .font(.appNumber(13, weight: .medium))
                            .foregroundStyle(Theme.secondaryText.opacity(0.7))
                            .monospacedDigit()
                    }
                case .scanning:
                    ProgressView().controlSize(.mini)
                case .done:
                    Text(result.totalSize > 0 ? result.totalSize.formattedBytes : "—")
                        .font(.appNumber(13, weight: .semibold))
                        .foregroundStyle(result.totalSize > 0 ? Theme.text : Theme.secondaryText)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText.opacity(0.6))
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct HistoryPanel: View {
    let history: [StatsStore.CleanupRecord]

    var body: some View {
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent cleanups").font(.app(15, weight: .bold))
                ForEach(history.prefix(6)) { record in
                    HStack {
                        Text(record.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.app(12.5))
                        Text("\(record.items) items")
                            .font(.app(12))
                            .foregroundStyle(Theme.secondaryText)
                        if record.removedByTools > 0 {
                            Text("· \(record.removedByTools.formattedBytes) removed by tools")
                                .font(.app(12))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Text(record.bytes.formattedBytes)
                            .font(.appNumber(13, weight: .semibold))
                            .monospacedDigit()
                    }
                    if record.id != history.prefix(6).last?.id { Divider() }
                }
            }
        }
    }
}

/// The disk by kind of data, from this session's analysis or the saved summary of the last one.
private struct StoragePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let summary = model.stats.stats.lastStorage
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("What takes your disk", systemImage: "chart.bar.xaxis")
                        .font(.app(15, weight: .bold))
                    if model.isAnalyzingStorage {
                        ProgressView().controlSize(.mini)
                        Text("Analyzing…").font(.app(12)).foregroundStyle(Theme.secondaryText)
                    } else if let summary {
                        Text(summary.date.relativeDescription).font(.app(12)).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    if summary != nil || model.storage != nil {
                        Button("Details") { model.navigate(to: .storage) }.buttonStyle(.link)
                    } else if !model.isAnalyzingStorage {
                        Button("Analyze") { model.analyzeStorage() }.buttonStyle(.link)
                    }
                }
                if let report = model.storage {
                    StorageBar(report: report)
                    legend(report.sortedBuckets, notMeasured: report.notMeasured)
                } else if let summary {
                    StorageBar(summary: summary)
                    legend(summary.sortedBuckets, notMeasured: summary.notMeasured)
                } else if !model.isAnalyzingStorage {
                    Text("Analyze to see apps, photos, videos, developer data and more, and where they live.")
                        .font(.app(12.5))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private func legend(_ buckets: [(bucket: StorageBucket, bytes: Int64)], notMeasured: Int64) -> some View {
        let columns = [GridItem(.adaptive(minimum: 190), spacing: 10, alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(buckets.prefix(8), id: \.bucket) { entry in
                legendItem(entry.bucket.color, entry.bucket.title, entry.bytes)
            }
            if notMeasured > 0 {
                legendItem(Theme.secondaryText.opacity(0.35), String(localized: "macOS and System Data"), notMeasured)
            }
        }
    }

    private func legendItem(_ color: Color, _ title: String, _ bytes: Int64) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).font(.app(12)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(bytes.formattedBytes).font(.appNumber(12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
        }
    }
}
