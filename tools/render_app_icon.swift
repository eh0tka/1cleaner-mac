// Renders the macOS app icon set from the iPhone 1Cleaner icon: the artwork inside Apple's macOS icon shape
// (824 pt rounded square on a 1024 canvas) with a soft shadow.
// Run from the app folder: swift tools/render_app_icon.swift <1024 px artwork.png>
import AppKit

guard CommandLine.arguments.count == 2 else { fatalError("Usage: swift tools/render_app_icon.swift <artwork.png>") }
let source = CommandLine.arguments[1]
let output = "OneCleanerMac/Resources/Assets.xcassets/AppIcon.appiconset"

guard let artwork = NSImage(contentsOfFile: source),
      let cgArtwork = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Missing \(source)")
}

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = size / 1024
    let body = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let shape = CGPath(roundedRect: body, cornerWidth: 185.4 * scale, cornerHeight: 185.4 * scale, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale,
                      color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(shape)
    context.setFillColor(CGColor(red: 1, green: 0.42, blue: 0.07, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.addPath(shape)
    context.clip()
    context.interpolationQuality = .high
    context.draw(cgArtwork, in: body)

    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! render(pixels: points * scale).write(to: URL(fileURLWithPath: "\(output)/\(name)"))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: "\(output)/Contents.json"))
print("Rendered \(images.count) icons into \(output)")
