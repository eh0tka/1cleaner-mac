import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Crypto addresses for optional support of the developer (the site version is free, no payment
/// provider). The same addresses are published on onebuckapps.com/donate/ so people can compare them. Changing an address
/// is the maintainer's decision only.
struct DonationNetwork: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Networks that use this address.
    let networks: String
    /// What can be sent there.
    let coins: String
    let address: String

    static let all: [DonationNetwork] = [
        DonationNetwork(id: "evm", title: "Ethereum & EVM", networks: "Ethereum, Arbitrum, BNB Chain",
                        coins: "USDT, USDC, ETH, BNB", address: "0x131B8Cf998B81f298eC5e62807A6A6292D72E870"),
        DonationNetwork(id: "tron", title: "Tron", networks: "Tron (TRC-20)",
                        coins: "USDT, TRX", address: "TMRiWQeDCxb9B64eYu6Ksn9XMk4BntZLWj"),
        DonationNetwork(id: "solana", title: "Solana", networks: "Solana",
                        coins: "USDT, USDC, SOL", address: "2u7TNXnmStRovWfrNn4WCHB3314PmsHBAbEw1Xq2T7GB"),
        DonationNetwork(id: "ton", title: "TON", networks: "TON",
                        coins: "USDT, TON", address: "UQCcrzCRkHnegfsqHKXaOvT0vDjSoAGVpHDUDj10MLzqswrg"),
        DonationNetwork(id: "btc", title: "Bitcoin", networks: "Bitcoin",
                        coins: "BTC", address: "bc1q5hxt0apm67zj5kg3hzfeehfkpsz4vqhgf7sha3"),
    ]
}

enum QRCode {
    /// A QR code of `text` as a crisp image (the plain address, which every wallet reads), made on the device.
    static func image(for text: String, size: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = max(1, (size * 2 / output.extent.width).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}
