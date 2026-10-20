import AppKit
import SwiftUI

/// Optional crypto support for the developer: the toolbar heart, and once after the first successful cleanup. Nothing is paid inside the app; it shows addresses to copy or scan.
struct SupportView: View {
    @Environment(\.dismiss) private var dismiss
    /// Space the cleanup that opened this sheet freed; nil when opened from the heart.
    var freed: Int64?
    @State private var network = Self.initialNetwork
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
            footer
        }
        .padding(24)
        // Never smaller than its content: the sheet always shows everything at once.
        .frame(minWidth: 720, idealWidth: 720, minHeight: 500, alignment: .top)
        .fixedSize()
    }

    private static var initialNetwork: DonationNetwork {
        #if DEBUG
        // `-supportNetwork <index>`: snapshots of the sheet with another network selected.
        let index = UserDefaults.standard.integer(forKey: "supportNetwork")
        if DonationNetwork.all.indices.contains(index) { return DonationNetwork.all[index] }
        #endif
        return DonationNetwork.all[0]
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(freed.map { String(localized: "\($0.formattedBytes) freed. Support 1Cleaner?") }
                        ?? String(localized: "Support 1Cleaner"))
                        .font(.app(20, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("""
                        1Cleaner is free: no ads, no tracking, no subscription. If it saved you space or time, \
                        you can thank the developer with crypto. Any amount helps keep it free.
                        """)
                        .font(.app(13))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Picker("Network", selection: $network) {
                ForEach(DonationNetwork.all) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            HStack(alignment: .center, spacing: 20) {
                if let image = QRCode.image(for: network.address, size: 168) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 168, height: 168)
                        .padding(10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline))
                        .accessibilityLabel("QR code of the \(network.title) address")
                }
                VStack(alignment: .leading, spacing: 10) {
                    labeled("Network", network.networks)
                    labeled("Send", network.coins)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Address").font(.app(11.5, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                        // An address too long for one line of the column is shown in two halves; Copy Address
                        // copies it whole.
                        Text(Self.displayed(network.address))
                            .font(.system(size: 12.5, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(network.address, forType: .string)
                        copied = true
                    } label: {
                        Label(copied ? String(localized: "Copied") : String(localized: "Copy Address"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: network) { copied = false }

            NoteBanner(text: String(localized: """
                Send only on the networks listed above. Coins sent on another network can't be recovered.
                """), tone: .warning)
        }
    }

    private var footer: some View {
        HStack {
            Text("The same addresses are on onebuckapps.com/donate.")
                .font(.app(11.5))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Button(freed == nil ? String(localized: "Done") : String(localized: "Not Now")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// The address as shown: in two halves when longer than one line of the column holds.
    private static func displayed(_ address: String) -> String {
        guard address.count > 52 else { return address }
        let middle = address.index(address.startIndex, offsetBy: (address.count + 1) / 2)
        return address[..<middle] + "\n" + address[middle...]
    }

    private func labeled(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.app(11.5, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            Text(value).font(.app(13.5, weight: .medium))
        }
    }
}
