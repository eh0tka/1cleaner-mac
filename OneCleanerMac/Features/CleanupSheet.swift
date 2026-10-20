import SwiftUI

/// Confirmation, progress and result of one cleanup.
struct CleanupSheet: View {
    @Environment(AppModel.self) private var model
    let session: CleanupSession
    @State private var confirmPermanent = false
    @State private var confirmEmptyTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch session.phase {
            case .confirming: confirmation
            case .running: running
            case .finished: finished
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(Theme.background)
        .confirmationDialog("Remove \(session.permanentItems.count) items for good?", isPresented: $confirmPermanent) {
            Button("Remove for Good and Clean", role: .destructive) { model.startCleanup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Docker and Xcode remove these items without the Trash. This can't be undone.")
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

    // MARK: Confirm

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clean \(session.items.reduce(0) { $0 + $1.size }.formattedBytes)?")
                .font(.app(22, weight: .bold))
            let risky = session.items.filter { $0.safety == .risky }
            if !risky.isEmpty {
                let names = risky.prefix(3).map(\.title).joined(separator: ", ") + (risky.count > 3 ? "…" : "")
                NoteBanner(text: String(localized: """
                    \(risky.count) selected items are marked Risky: \(names). \
                    They may hold data that exists nowhere else.
                    """, comment: "The names are the first three item titles, comma-separated"), tone: .warning)
            }
            if !session.trashItems.isEmpty {
                summary(
                    title: "Move to the Trash",
                    subtitle: String(localized: "You can put them back from the Trash until you empty it."),
                    items: session.trashItems,
                    color: Theme.accentDeep
                )
            }
            if !session.permanentItems.isEmpty {
                summary(
                    title: "Remove for good",
                    subtitle: session.extraContainers == 0
                        ? String(localized: "Docker and Xcode remove these themselves. This can't be undone.")
                        : String(localized: """
                            Docker and Xcode remove these themselves. This can't be undone. Docker also removes \
                            \(session.extraContainers) stopped containers of the selected images.
                            """),
                    items: session.permanentItems,
                    color: Theme.danger
                )
            }
            HStack {
                Spacer()
                Button("Cancel") { model.closeCleanup() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(session.permanentItems.isEmpty ? String(localized: "Move to Trash") : String(localized: "Clean…")) {
                    if session.permanentItems.isEmpty { model.startCleanup() } else { confirmPermanent = true }
                }
                .buttonStyle(PrimaryButtonStyle(destructive: !session.permanentItems.isEmpty))
            }
        }
    }

    private func summary(title: LocalizedStringKey, subtitle: String, items: [CleanupItem], color: Color) -> some View {
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.app(15, weight: .bold)).foregroundStyle(color)
                    Spacer()
                    Text(items.reduce(0) { $0 + $1.size }.formattedBytes)
                        .font(.appNumber(15))
                        .foregroundStyle(color)
                }
                Text(subtitle).font(.app(12)).foregroundStyle(Theme.secondaryText)
                let byCategory = Dictionary(grouping: items, by: \.category)
                ForEach(CategoryID.allCases.filter { byCategory[$0] != nil }) { category in
                    let group = byCategory[category] ?? []
                    HStack {
                        Label(category.title, systemImage: category.systemImage)
                            .font(.app(12.5))
                        Text("\(group.count) items")
                            .font(.app(12))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Text(group.reduce(0) { $0 + $1.size }.formattedBytes)
                            .font(.appNumber(12.5, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: Running

    private var running: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cleaning…").font(.app(22, weight: .bold))
            ProgressView(value: Double(session.processed), total: Double(max(session.items.count, 1)))
                .tint(Theme.accent)
            Text("\(session.processed) of \(session.items.count) · \(session.current)")
                .font(.app(12.5))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Spacer()
                Button(session.stopRequested ? String(localized: "Stopping…") : String(localized: "Stop")) { model.stopCleanup() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(session.stopRequested)
            }
        }
    }

    // MARK: Result

    private var finished: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: session.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(session.failures.isEmpty ? Theme.success : Theme.warning)
                (session.stopped ? Text("Cleaning stopped") : Text("Cleaning finished"))
                    .font(.app(22, weight: .bold))
            }
            Panel(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    if session.movedToTrash > 0 {
                        resultLine("Moved to the Trash", session.movedToTrash)
                    }
                    if session.removedByTools > 0 {
                        resultLine("Removed by Docker and Xcode", session.removedByTools)
                    }
                    if let before = session.freeBefore, let after = session.freeAfter {
                        Divider()
                        HStack {
                            Text("Free space").font(.app(13))
                            Spacer()
                            Text("\(before.formattedBytes) → \(after.formattedBytes)")
                                .font(.appNumber(13, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                }
            }
            if session.movedToTrash > 0, !session.trashEmptied {
                NoteBanner(text: String(localized: """
                    Files in the Trash still take space. Empty the Trash to get it back, or check them in Finder first.
                    """))
            }
            if session.trashEmptied {
                NoteBanner(text: String(localized: "The Trash is empty."))
            }
            if !session.failures.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(session.failures.count) not removed")
                        .font(.app(13, weight: .semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(session.failures) { failure in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(failure.title).font(.app(12, weight: .medium))
                                    Text(failure.reason).font(.app(11.5)).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
            }
            HStack {
                if session.movedToTrash > 0, !session.trashEmptied {
                    Button("Empty Trash…") { confirmEmptyTrash = true }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.isEmptyingTrash)
                    if model.isEmptyingTrash { ProgressView().controlSize(.small) }
                }
                Spacer()
                Button("Done") { model.closeCleanup() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isEmptyingTrash)
            }
        }
    }

    private func resultLine(_ title: LocalizedStringKey, _ bytes: Int64) -> some View {
        HStack {
            Text(title).font(.app(13))
            Spacer()
            Text(bytes.formattedBytes).font(.appNumber(15)).monospacedDigit()
        }
    }
}
