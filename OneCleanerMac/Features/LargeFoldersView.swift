import SwiftUI

/// Folders that are big because of a mass of small files (dependency trees, caches, exported image sets), from the
/// Storage analysis. Read-only.
struct LargeFoldersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.isAnalyzingStorage { progressPanel }
                if let report = model.storage {
                    Text("""
                        Folders where thousands of files under \(StorageAnalyzer.minimumListedFile.formattedBytes) add \
                        up to \(StorageAnalyzer.largeFolderSmallBytes.formattedBytes) or more. A listed folder can \
                        hold another listed folder.
                        """)
                        .font(.app(12.5))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    NoteBanner(text: String(localized: """
                        View only: nothing here is selected or removed. Clean caches and build folders in their own \
                        sections.
                        """, comment: "Note on the Large Folders screen"))
                    if !report.measuredWithFullDiskAccess, !model.fullDiskAccess {
                        HStack(spacing: 12) {
                            VStack(spacing: 8) {
                                ForEach(report.notes, id: \.self) { NoteBanner(text: $0) }
                            }
                            Button("Open Settings") { SystemAccess.openFullDiskAccessSettings() }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    if report.largeFolders.isEmpty {
                        Panel(padding: 24) {
                            Text("No folder full of small files was found.")
                                .font(.app(14))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    } else {
                        foldersList(report.largeFolders)
                    }
                } else if !model.isAnalyzingStorage {
                    Panel(padding: 24) {
                        HStack {
                            Text("See the folders that are big because of thousands of small files.")
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
        .navigationTitle("Large Folders")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Large Folders").font(.app(24, weight: .bold))
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

    private func foldersList(_ folders: [StorageReport.LargeFolder]) -> some View {
        let largest = folders.map(\.bytes).max() ?? 1
        return VStack(spacing: 0) {
            ForEach(folders) { folder in
                HStack {
                    UsageRow(
                        icon: folder.kind?.systemImage ?? "folder.fill", color: folder.kind?.color ?? Theme.accent,
                        title: (folder.path as NSString).lastPathComponent,
                        detail: PathDisplay.abbreviated(folder.path) + " · " + String(localized: """
                            \(folder.fileCount) files, \(folder.smallBytes.formattedBytes) in files under \
                            \(StorageAnalyzer.minimumListedFile.formattedBytes)
                            """, comment: "Large Folders row: files inside and how much the small ones take"),
                        bytes: folder.bytes, total: largest, chevron: false
                    )
                    Button {
                        SystemAccess.reveal(folder.path)
                    } label: {
                        Image(systemName: "magnifyingglass.circle").font(.system(size: 15))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                    .padding(.trailing, 14)
                }
                .contextMenu { Button("Show in Finder") { SystemAccess.reveal(folder.path) } }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }
}
