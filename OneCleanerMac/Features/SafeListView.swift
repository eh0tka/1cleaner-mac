import AppKit
import SwiftUI

/// Everything the person put on the Safe List, with a way to take it off again.
struct SafeListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Text("""
                    Items and folders here never appear in scans and can't be cleaned by mistake. Add an item or \
                    its whole project from the ••• menu of any row.
                    """)
                    .font(.app(13))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                itemsSection
                foldersSection
            }
            .padding(28)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Safe List")
    }

    private var header: some View {
        let items = model.settings.safeItems.count
        let folders = model.settings.safeFolders.count
        return HStack(spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Safe List").font(.app(24, weight: .bold))
                Text("\(items) items · \(folders) folders")
                    .font(.app(12.5))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button {
                addFolder()
            } label: {
                Label("Add Folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Items").font(.app(15, weight: .semibold))
            rows {
                if model.settings.safeItems.isEmpty {
                    emptyRow("No items yet.")
                }
                ForEach(Array(model.settings.safeItems.reversed().enumerated()), id: \.element) { index, id in
                    if index > 0 { Divider().padding(.leading, 52) }
                    itemRow(id)
                }
            }
            Text("Taking an item off the list scans its category again, so it shows up right away.")
                .font(.app(11.5))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Folders — nothing inside is shown").font(.app(15, weight: .semibold))
            rows {
                if model.settings.safeFolders.isEmpty {
                    emptyRow("No folders yet.")
                }
                ForEach(Array(model.settings.safeFolders.enumerated()), id: \.element) { index, folder in
                    if index > 0 { Divider().padding(.leading, 52) }
                    row(
                        icon: "folder.fill", title: (folder as NSString).lastPathComponent,
                        detail: PathDisplay.abbreviated(folder), path: folder
                    ) {
                        model.settings.removeSafeFolder(folder)
                    }
                }
            }
            Text("A folder taken off the list shows up again in the next scan.")
                .font(.app(11.5))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func itemRow(_ id: String) -> some View {
        let info = model.settings.safeItemInfo[id]
        let category = info?.categoryID
        var detail = [
            category?.title, info.map { $0.size.formattedBytes },
            info.map { String(localized: "added \($0.added.relativeDescription)") },
        ]
            .compactMap { $0 }
            .joined(separator: " · ")
        let path = info?.path ?? (id.hasPrefix("/") ? id : nil)
        if let path { detail += (detail.isEmpty ? "" : " · ") + PathDisplay.abbreviated(path) }
        return row(
            icon: category?.systemImage ?? "doc",
            title: info?.title ?? (id.hasPrefix("/") ? (id as NSString).lastPathComponent : id),
            detail: detail, path: path
        ) {
            model.removeFromSafeList(id)
        }
    }

    private func row(
        icon: String, title: String, detail: String, path: String?, remove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(13.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.app(11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let path, FileInfo.exists(path) {
                Button {
                    SystemAccess.reveal(path)
                } label: {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }
            Button("Remove from List", action: remove)
                .buttonStyle(.link)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func emptyRow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.app(13))
            .foregroundStyle(Theme.secondaryText)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rows<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add to Safe List")
        if panel.runModal() == .OK {
            for url in panel.urls { model.settings.addSafeFolder(url.path) }
            model.removeSafeItemsFromResults()
        }
    }
}
