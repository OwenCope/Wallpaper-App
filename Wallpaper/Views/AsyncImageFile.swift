import SwiftUI
import ImageIO

/// Loads a downsampled thumbnail off the main thread so the grid stays smooth.
struct AsyncImageFile: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        let thumb = await Task.detached(priority: .userInitiated) {
            Self.downsample(url, maxPixel: 1200)   // crisp on large/Retina cards
        }.value
        if !Task.isCancelled { image = thumb }
    }

    /// Use ImageIO to decode a downsampled thumbnail — cheap on memory and CPU.
    static func downsample(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOptions) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}
