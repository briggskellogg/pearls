import SwiftUI
import ImageIO

struct PearlsThumbnailView: View {
    let url: URL
    var maxPixelSize: Int = 1200
    @State private var thumbnail: CGImage?
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.primary.opacity(0.035)
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else if finished {
                Image(systemName: "photo")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: url) {
            thumbnail = nil
            finished = false
            let sourceURL = url
            let maximum = maxPixelSize
            let result = await Task.detached(priority: .utility) {
                makePearlsThumbnail(url: sourceURL, maxPixelSize: maximum)
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = result
            finished = true
        }
    }
}

private func makePearlsThumbnail(url: URL, maxPixelSize: Int) -> CGImage? {
    guard url.isFileURL,
          let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceShouldCacheImmediately: true
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

struct PearlsFullImageView: View {
    let url: URL
    @State private var thumbnail: CGImage?
    @State private var finished = false

    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else if finished {
                ContentUnavailableView("Image preview unavailable", systemImage: "photo", description: Text("You can still share the original file."))
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .task(id: url) {
            thumbnail = nil
            finished = false
            let sourceURL = url
            let result = await Task.detached(priority: .utility) {
                makePearlsThumbnail(url: sourceURL, maxPixelSize: 2400)
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = result
            finished = true
        }
    }
}
