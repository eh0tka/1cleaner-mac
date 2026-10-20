import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            scanFolders
                .tabItem { Label("Scan Folders", systemImage: "folder") }
            access
                .tabItem { Label("Access", systemImage: "lock.shield") }
        }
        .frame(width: 600, height: 440)
    }

    private var scanFolders: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1Cleaner looks for project build folders and large files in these folders.")
                .font(.app(12.5))
                .foregroundStyle(Theme.secondaryText)
            List {
                ForEach(model.settings.scanRoots, id: \.self) { root in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                        Text(PathDisplay.abbreviated(root))
                        Spacer()
                        Button("Remove") { model.settings.removeRoot(root) }
                            .buttonStyle(.link)
                    }
                }
            }
            .listStyle(.bordered)
            HStack {
                Button("Add Folder…") { addFolder() }
                Spacer()
                Text("Changes apply to the next scan.").font(.app(11.5)).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(20)
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: model.fullDiskAccess ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 22))
                    .foregroundStyle(model.fullDiskAccess ? Theme.success : Theme.secondaryText)
                (model.fullDiskAccess ? Text("Full Disk Access is on") : Text("Full Disk Access is off"))
                    .font(.app(15, weight: .semibold))
            }
            Text("""
                Optional. With it, 1Cleaner also measures the Trash, Safari's cache and caches macOS protects. \
                1Cleaner reads files only on this Mac, for example to compare duplicates, and sends nothing anywhere.
                """)
                .font(.app(12.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Privacy Settings") { SystemAccess.openFullDiskAccessSettings() }
                Button("Check Again") { Task { await model.refreshSystemState() } }
            }
            Spacer()
        }
        .padding(20)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add", comment: "Button of the folder picker that adds scan folders")
        if panel.runModal() == .OK {
            for url in panel.urls { model.settings.addRoot(url.path) }
        }
    }
}
