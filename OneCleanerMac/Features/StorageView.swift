import SwiftUI

/// What takes the disk: kinds of data → the folders holding them → the largest files. Read-only.
struct StorageView: View {
    @Environment(AppModel.self) private var model
    @State private var bucket: StorageBucket?
    @State private var folder: StorageReport.FolderUsage?
    /// A subfolder of `folder` being looked at; nil is `folder` itself.
    @State private var subpath: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.isAnalyzingStorage { progressPanel }
                if let report = model.storage {
                    StorageBar(report: report)
                    if !report.notes.isEmpty {
                        HStack(spacing: 12) {
                            VStack(spacing: 8) {
                                ForEach(report.notes, id: \.self) { NoteBanner(text: $0) }
                            }
                            if !report.measuredWithFullDiskAccess, !model.fullDiskAccess {
                                Button("Open Settings") { SystemAccess.openFullDiskAccessSettings() }
                                    .buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }
                    breadcrumb
                    if let bucket, let folder {
                        filesList(folder, bucket: bucket)
                    } else if let bucket {
                        foldersList(report, bucket: bucket)
                    } else {
                        bucketsList(report)
                    }
                } else if !model.isAnalyzingStorage {
                    Panel(padding: 24) {
                        HStack {
                            Text("See what kind of data fills your disk and where it lives.")
                                .font(.app(14))
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Button("Analyze") { model.analyzeStorage() }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Storage")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Storage").font(.app(24, weight: .bold))
                if let report = model.storage {
                    Text("\(report.diskUsed.formattedBytes) used · analyzed \(report.date.relativeDescription)")
                        .font(.app(12.5))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            if model.storage != nil, !model.isAnalyzingStorage {
                Button {
                    model.analyzeStorage()
                } label: {
                    Label("Analyze Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var progressPanel: some View {
        Panel(padding: 20) {
            HStack(spacing: 14) {
                ProgressView().controlSize(.small)
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text("Analyzing… \(model.storageProgress.snapshot.entries) files")
                        .font(.app(14, weight: .medium))
                }
                Spacer()
                Button("Stop") { model.stopStorageAnalysis() }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var breadcrumb: some View {
        if let bucket {
            HStack(spacing: 6) {
                Button("All") {
                    self.bucket = nil
                    folder = nil
                    subpath = nil
                }
                .buttonStyle(.link)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                if let folder {
                    Button(bucket.title) {
                        self.folder = nil
                        subpath = nil
                    }
                    .buttonStyle(.link)
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                    if let subpath {
                        Button(PathDisplay.abbreviated(folder.path)) { self.subpath = nil }.buttonStyle(.link)
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                        Text(relative(subpath, to: folder.path)).lineLimit(1).truncationMode(.middle)
                    } else {
                        Text(PathDisplay.abbreviated(folder.path)).lineLimit(1).truncationMode(.middle)
                    }
                } else {
                    Text(bucket.title)
                }
            }
            .font(.app(13, weight: .semibold))
        }
    }

    private func bucketsList(_ report: StorageReport) -> some View {
        rows {
            ForEach(report.sortedBuckets, id: \.bucket) { entry in
                Button {
                    bucket = entry.bucket
                } label: {
                    UsageRow(
                        icon: entry.bucket.systemImage, color: entry.bucket.color, title: entry.bucket.title,
                        detail: folderCount(report.folders[entry.bucket]?.count ?? 0),
                        bytes: entry.bytes, total: report.diskUsed, chevron: true
                    )
                }
                .buttonStyle(.plain)
            }
            if report.notMeasured > 0 {
                UsageRow(
                    icon: "gearshape", color: Theme.secondaryText.opacity(0.35),
                    title: String(localized: "macOS and System Data"),
                    detail: String(localized: "System files, other users, snapshots and data 1Cleaner can't read"),
                    bytes: report.notMeasured, total: report.diskUsed, chevron: false
                )
            }
        }
    }

    private func foldersList(_ report: StorageReport, bucket: StorageBucket) -> some View {
        let folders = report.folders[bucket] ?? []
        return rows {
            ForEach(folders.prefix(100)) { usage in
                Button {
                    folder = usage
                    subpath = nil
                } label: {
                    UsageRow(
                        icon: "folder.fill", color: bucket.color, title: (usage.path as NSString).lastPathComponent,
                        detail: PathDisplay.abbreviated(usage.path) + " · " + fileCount(usage.fileCount),
                        bytes: usage.bytes,
                        total: report.totals[bucket] ?? 1, chevron: !usage.files.isEmpty || !usage.subfolders.isEmpty
                    )
                }
                .buttonStyle(.plain)
                .disabled(usage.files.isEmpty && usage.subfolders.isEmpty)
                .contextMenu { Button("Show in Finder") { SystemAccess.reveal(usage.path) } }
            }
        }
    }

    /// Inside a folder: its biggest subfolders of this kind, then its largest files.
    private func filesList(_ usage: StorageReport.FolderUsage, bucket: StorageBucket) -> some View {
        let current = subpath ?? usage.path
        let totals = subpath.flatMap { usage.subfolders[$0] }
        let bytes = totals?.bytes ?? usage.bytes
        let count = totals?.fileCount ?? usage.fileCount
        let children = usage.children(of: current)
        let files = usage.files.filter { $0.path.hasPrefix(current + "/") }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(count) files, \(bytes.formattedBytes).")
                    .font(.app(12))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button("Show Folder in Finder") { SystemAccess.reveal(current) }.buttonStyle(.link)
            }
            if !children.isEmpty {
                Text("Folders").font(.app(13, weight: .semibold))
                rows {
                    ForEach(children, id: \.path) { child in
                        let target = usage.collapsed(child.path)
                        Button {
                            subpath = target
                        } label: {
                            UsageRow(
                                icon: "folder.fill", color: bucket.color, title: relative(target, to: current),
                                detail: fileCount(child.usage.fileCount), bytes: child.usage.bytes, total: bytes,
                                chevron: true
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Show in Finder") { SystemAccess.reveal(target) } }
                    }
                }
            }
            (files.isEmpty
                ? Text("""
                    No single file here is \(StorageAnalyzer.minimumListedFile.formattedBytes) or larger among the \
                    largest of this folder.
                    """)
                : Text("""
                    Largest files; files under \(StorageAnalyzer.minimumListedFile.formattedBytes) count only in \
                    the totals.
                    """))
                .font(.app(12))
                .foregroundStyle(Theme.secondaryText)
            if !files.isEmpty {
                rows {
                    ForEach(files) { file in
                        HStack {
                            UsageRow(
                                icon: bucket.systemImage, color: bucket.color, title: (file.path as NSString).lastPathComponent,
                                detail: PathDisplay.abbreviated((file.path as NSString).deletingLastPathComponent),
                                bytes: file.bytes, total: bytes, chevron: false
                            )
                            Button {
                                SystemAccess.reveal(file.path)
                            } label: {
                                Image(systemName: "magnifyingglass.circle").font(.system(size: 15))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .help("Show in Finder")
                            .padding(.trailing, 14)
                        }
                    }
                }
            }
        }
    }

    /// `path` relative to `base`: "apps/1cleaner/marketing".
    private func relative(_ path: String, to base: String) -> String {
        path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : PathDisplay.abbreviated(path)
    }

    private func fileCount(_ count: Int) -> String {
        String(localized: "\(count) files")
    }

    /// The report keeps the 200 largest folders per kind.
    private func folderCount(_ count: Int) -> String {
        count >= 200 ? String(localized: "200+ folders") : String(localized: "\(count) folders")
    }

    private func rows<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }
}

struct UsageRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let bytes: Int64
    let total: Int64
    let chevron: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.app(13.5, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(bytes.formattedBytes).font(.appNumber(13.5, weight: .semibold)).monospacedDigit()
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.hairline)
                        Capsule().fill(color)
                            .frame(width: max(2, proxy.size.width * CGFloat(bytes) / CGFloat(max(total, 1))))
                    }
                }
                .frame(height: 5)
                Text(detail)
                    .font(.app(11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// One stacked bar of the disk: each kind of data in its color, then macOS and system data in grey.
struct StorageBar: View {
    let segments: [(color: Color, bytes: Int64)]
    let total: Int64

    init(report: StorageReport) {
        segments = report.sortedBuckets.map { ($0.bucket.color, $0.bytes) }
            + [(Theme.secondaryText.opacity(0.35), report.notMeasured)]
        total = max(report.diskUsed, report.measured)
    }

    init(summary: StatsStore.StorageSummary) {
        segments = summary.sortedBuckets.map { ($0.bucket.color, $0.bytes) }
            + [(Theme.secondaryText.opacity(0.35), summary.notMeasured)]
        total = segments.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if segment.bytes > 0 {
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(2, (proxy.size.width - CGFloat(segments.count * 2))
                                * CGFloat(segment.bytes) / CGFloat(max(total, 1))))
                    }
                }
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .frame(height: 22)
    }
}
