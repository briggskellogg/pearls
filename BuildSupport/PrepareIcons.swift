import AppKit
import ImageIO
import UniformTypeIdentifiers

// Mechanical asset-catalog packaging preserves the supplied artwork and keeps
// the original file unchanged. iOS marketing icons require an opaque image.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: PrepareIcons.swift SOURCE_PNG ASSET_CATALOG")
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let catalog = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let sourceImage = NSImage(contentsOf: source),
      let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("The supplied Pearls mark could not be read.")
}

func makePNG(size: Int, at url: URL) throws {
    guard let context = CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.setFillColor(CGColor(red: 0.965, green: 0.973, blue: 0.985, alpha: 1))
    let bounds = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
    context.fill(bounds)
    context.interpolationQuality = .high
    context.draw(cgImage, in: bounds)
    guard let result = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL,
              UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, result, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

func writeSet(_ name: String, slots: [(String, Double, Int)]) throws {
    let directory = catalog.appendingPathComponent(name + ".appiconset", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var rendered = Set<Int>()
    var images: [[String: String]] = []
    for (idiom, points, scale) in slots {
        let pixels = Int(points * Double(scale))
        let filename = "AppIcon-\(pixels).png"
        if rendered.insert(pixels).inserted {
            try makePNG(size: pixels, at: directory.appendingPathComponent(filename))
        }
        let dimension = points.rounded() == points ? String(Int(points)) : String(points)
        images.append(["idiom": idiom, "size": "\(dimension)x\(dimension)",
                       "scale": "\(scale)x", "filename": filename])
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: directory.appendingPathComponent("Contents.json"), options: .atomic)
}

var mac: [(String, Double, Int)] = []
for points in [16.0, 32, 128, 256, 512] {
    for scale in [1, 2] { mac.append(("mac", points, scale)) }
}
var ios: [(String, Double, Int)] = [("ios-marketing", 1024, 1)]
for points in [20.0, 29, 40, 60] {
    for scale in [2, 3] { ios.append(("iphone", points, scale)) }
}
for points in [20.0, 29, 40, 76] {
    for scale in [1, 2] { ios.append(("ipad", points, scale)) }
}
ios.append(("ipad", 83.5, 2))
try writeSet("AppIcon-Mac", slots: mac)
try writeSet("AppIcon-iOS", slots: ios)
print("Packaged Pearls app icons for macOS and iPhone.")
