import AppKit
import SwiftUI

/// Renders app-generated gradient wallpapers at full screen resolution.
enum GradientGenerator {

    struct Preset: Identifiable, Hashable {
        let id: String
        let name: String
        let colors: [Color]
        let angle: Double   // degrees
    }

    static let presets: [Preset] = [
        .init(id: "dusk", name: "Dusk", colors: [.indigo, .purple, .pink], angle: 135),
        .init(id: "ocean", name: "Ocean", colors: [.teal, .blue, .indigo], angle: 115),
        .init(id: "sunrise", name: "Sunrise", colors: [.orange, .pink, .purple], angle: 90),
        .init(id: "forest", name: "Forest", colors: [.green, .teal, .black], angle: 160),
        .init(id: "mono", name: "Graphite", colors: [.gray, .black], angle: 135),
        .init(id: "candy", name: "Candy", colors: [.pink, .purple, .blue], angle: 45),
    ]

    /// Render a preset to a PNG sized for the main screen and return the file URL.
    static func render(_ preset: Preset) -> URL? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = NSScreen.main?.frame.size ?? CGSize(width: 2560, height: 1440)
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)

        // Catalog colors (.black/.gray) can't be interpolated by NSGradient,
        // so force every color into the sRGB space first.
        let nsColors = preset.colors.compactMap { NSColor($0).usingColorSpace(.sRGB) }
        guard nsColors.count == preset.colors.count,
              let gradient = NSGradient(colors: nsColors) else { return nil }

        // Draw straight into a pixel-accurate bitmap.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        gradient.draw(in: NSRect(origin: .zero, size: pixelSize), angle: CGFloat(preset.angle))
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }

        let dest = AppPaths.generated.appendingPathComponent("gradient-\(preset.id).png")
        do { try png.write(to: dest) } catch { return nil }
        return dest
    }
}
