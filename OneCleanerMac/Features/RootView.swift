import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var columns = Self.initialColumns

    /// `-hideSidebar YES` (debug): opens without the sidebar, for snapshots taken while the screen is locked, which
    /// can't draw the sidebar.
    private static var initialColumns: NavigationSplitViewVisibility {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "hideSidebar") { return .detailOnly }
        #endif
        // The sidebar is open at every launch: without it the window looks empty.
        return .all
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 300)
        } detail: {
            Group {
                switch model.destination ?? .overview {
                case .overview: OverviewView()
                case .storage: StorageView()
                case .category(let category): CategoryView(category: category)
                case .safeList: SafeListView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.app(13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().stroke(Theme.hairline))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                        .padding(.bottom, 84)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.toast)
            .sheet(item: $model.move) { session in
                MoveSheet(session: session)
                    .interactiveDismissDisabled(session.outcome == nil)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.hasResults { SelectionBar() }
            }
            .toolbar {
                // Always on screen: support and About.
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.support = .manual
                    } label: {
                        Label("Support 1Cleaner", systemImage: "heart.fill")
                    }
                    .foregroundStyle(Theme.accent)
                    .help("Support the developer")
                    Button {
                        model.navigate(to: .about)
                    } label: {
                        Label("About 1Cleaner", systemImage: "info.circle")
                    }
                    .help("About, updates, privacy and support")
                }
            }
        }
        .tint(Theme.accent)
        .sheet(item: $model.support) { prompt in
            switch prompt {
            case .manual: SupportView()
            case .afterCleanup(let freed): SupportView(freed: freed)
            }
        }
        .sheet(item: $model.cleanup, onDismiss: { model.cleanupSheetClosed() }) { session in
            CleanupSheet(session: session)
                .interactiveDismissDisabled(session.phase == .running)
        }
        // Leaving a screen with checked items (see `AppModel.navigate(to:)`).
        .alert("Clean the selected items?", isPresented: Binding(
            get: { model.pendingDestination != nil },
            set: { if !$0 { model.pendingDestination = nil } }
        ), presenting: model.pendingDestination) { target in
            Button("Clean…") {
                model.pendingDestination = nil
                model.prepareCleanup()
            }
            Button("Clear Selection") { model.clearSelection(andGoTo: target) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("\(model.selectedSize.formattedBytes) is selected here. Clean it now, or clear the selection and go on.")
        }
        .alert("Couldn't empty the Trash", isPresented: Binding(
            get: { model.trashMessage != nil },
            set: { if !$0 { model.trashMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.trashMessage ?? "")
        }
    }
}

extension CleanupSession: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}

/// Selected size and the Clean button, under every screen.
struct SelectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let count = model.selectedItems.count
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedSize.formattedBytes)
                    .font(.appNumber(22))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                (count == 0 ? Text("Nothing selected") : Text("\(count) items selected"))
                    .font(.app(12))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if model.isBusyScanning {
                ProgressView().controlSize(.small)
                Text("Scanning…").font(.app(13)).foregroundStyle(Theme.secondaryText)
            }
            Button("Clean…") { model.prepareCleanup() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(count == 0 || model.isBusyScanning || model.move != nil)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}
