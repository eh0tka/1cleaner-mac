import SwiftUI

/// Progress and result of "Move to Another Disk".
struct MoveSheet: View {
    @Environment(AppModel.self) private var model
    let session: MoveSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch session.outcome {
            case nil:
                Text("Moving “\(session.item.title)”").font(.app(20, weight: .bold))
                Text("To \(PathDisplay.abbreviated(session.destination))")
                    .font(.app(12.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if session.total > 0 {
                    ProgressView(value: Double(session.copied), total: Double(session.total)).tint(Theme.accent)
                    Text("\(session.copied.formattedBytes) of \(session.total.formattedBytes) copied")
                        .font(.app(12))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Checking the files…").font(.app(12)).foregroundStyle(Theme.secondaryText)
                }
                NoteBanner(text: String(localized: """
                    The original stays where it is until the copy is checked; then it goes to the Trash.
                    """))
                HStack {
                    Spacer()
                    Button("Stop") { model.stopMove() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            case .moved(let destination):
                Label("Moved", systemImage: "checkmark.circle.fill")
                    .font(.app(20, weight: .bold))
                    .foregroundStyle(Theme.success)
                Text("""
                    “\(session.item.title)” is now in \(PathDisplay.abbreviated(destination)). \
                    The original is in the Trash; its space comes back when you empty the Trash.
                    """)
                    .font(.app(13))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Show Copy in Finder") { SystemAccess.reveal(destination) }
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button("Done") { model.closeMove() }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let reason):
                Label("Not moved", systemImage: "exclamationmark.circle.fill")
                    .font(.app(20, weight: .bold))
                    .foregroundStyle(Theme.warning)
                Text(reason)
                    .font(.app(13))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("OK") { model.closeMove() }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(Theme.background)
    }
}
