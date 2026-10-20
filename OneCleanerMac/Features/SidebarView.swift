import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(get: { model.destination }, set: { model.navigate(to: $0) })) {
            Label {
                Text("Dashboard")
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
            }
            .tag(SidebarDestination.overview)

            Label {
                Text("Storage")
            } icon: {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(Theme.accent)
            }
            .tag(SidebarDestination.storage)

            ForEach(CleanerGroup.allCases, id: \.self) { group in
                Section(group.title) {
                    ForEach(group.categories) { category in
                        SidebarRow(category: category)
                            .tag(SidebarDestination.category(category))
                            .contextMenu {
                                Button("Rescan \(category.title)") { model.rescan(category) }
                                    .disabled(model.isScanning || model.cleanup != nil
                                        || model.result(category).state == .scanning)
                            }
                    }
                }
            }

            Section {
                HStack {
                    Label {
                        Text("Safe List")
                    } icon: {
                        Image(systemName: "checkmark.shield").foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    let count = model.settings.safeItems.count + model.settings.safeFolders.count
                    if count > 0 {
                        Text(verbatim: "\(count)")
                            .font(.appNumber(11, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .monospacedDigit()
                    }
                }
                .tag(SidebarDestination.safeList)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                BrandMark(size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text("1Cleaner").font(.app(12, weight: .semibold))
                    Text("by 1Buck Apps").font(.app(10)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(12)
        }
    }
}

private struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    let category: CategoryID

    var body: some View {
        let result = model.result(category)
        HStack {
            Label {
                Text(category.title)
            } icon: {
                Image(systemName: category.systemImage).foregroundStyle(Theme.accent)
            }
            Spacer()
            switch result.state {
            case .idle:
                EmptyView()
            case .scanning:
                ProgressView().controlSize(.mini)
            case .done:
                let selected = model.selectedSize(in: [category])
                Text(result.totalSize > 0 ? result.totalSize.formattedBytes : "—")
                    .font(.appNumber(11, weight: .medium))
                    .foregroundStyle(selected > 0 ? Theme.accentDeep : Theme.secondaryText)
                    .monospacedDigit()
            }
        }
    }
}
