import AppKit
import ImageIO
import UniformTypeIdentifiers

// Trim transparent padding in memory, then scale the supplied artwork without
// changing its geometry or colors. Source PNGs remain unchanged.
guard CommandLine.arguments.count == 4 else {
    fatalError("Usage: PrepareIcons.swift SYMBOL_PNG MAKER_PNG ASSET_CATALOG")
}
let catalog = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func artwork(at path: String, alignmentAlpha: UInt8 = 1) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width > 0, image.height > 0, image.width <= 4096, image.height <= 4096 else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    return try pixels.withUnsafeMutableBytes { bytes in
        guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var left = width, right = -1, top = height, bottom = -1
        for y in 0..<height {
            for x in 0..<width where bytes[(y * width + x) * 4 + 3] >= alignmentAlpha {
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= left, bottom >= top else { throw CocoaError(.fileReadCorruptFile) }
        // Ignore insignificant alpha noise only when choosing the symbol's
        // alignment bounds. Keep every original pixel within the padded crop;
        // no threshold, recoloring, or shape filtering is applied to artwork.
        left = max(0, left - 2); top = max(0, top - 2)
        right = min(width - 1, right + 2); bottom = min(height - 1, bottom + 2)
        guard
              let normalized = context.makeImage(),
              let cropped = normalized.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return cropped
    }
}

let symbol = try artwork(at: CommandLine.arguments[1], alignmentAlpha: 16)
let maker = try artwork(at: CommandLine.arguments[2])

func aspectFit(_ image: CGImage, in bounds: CGRect) -> CGRect {
    let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
    let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
    return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
}

func makePNG(size: Int, opaque: Bool, at url: URL) throws {
    guard let context = CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let side = CGFloat(size)
    let bounds = CGRect(x: 0, y: 0, width: side, height: side)
    if opaque {
        // The default iOS / App Store raster contains no alpha channel.
        context.setFillColor(CGColor(red: 0.965, green: 0.973, blue: 0.985, alpha: 1))
        context.fill(bounds)
    } else { context.clear(bounds) }
    context.interpolationQuality = .high
    let symbolRect = aspectFit(symbol, in: bounds.insetBy(dx: side * 0.12, dy: side * 0.12))
    context.draw(symbol, in: symbolRect)
    let makerHeight = side * 0.15
    let makerWidth = makerHeight * CGFloat(maker.width) / CGFloat(maker.height)
    let makerRect = CGRect(x: side * 0.90 - makerWidth, y: side * 0.10, width: makerWidth, height: makerHeight)
    context.draw(maker, in: makerRect)
    guard let result = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL,
              UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, result, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

func writeSet(_ name: String, opaque: Bool, slots: [(String, Double, Int)]) throws {
    let directory = catalog.appendingPathComponent(name + ".appiconset", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var rendered = Set<Int>()
    var images: [[String: String]] = []
    for (idiom, points, scale) in slots {
        let pixels = Int(points * Double(scale))
        let filename = "AppIcon-\(pixels).png"
        if rendered.insert(pixels).inserted {
            try makePNG(size: pixels, opaque: opaque, at: directory.appendingPathComponent(filename))
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
try writeSet("AppIcon-Mac", opaque: false, slots: mac)
try writeSet("AppIcon-iOS", opaque: true, slots: ios)
print("Packaged symbol and maker icons: transparent macOS, opaque iPhone.")
