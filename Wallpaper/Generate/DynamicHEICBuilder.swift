import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Builds a macOS "dynamic" .heic wallpaper: a multi-image HEIC whose primary
/// image carries `apple_desktop` metadata telling the OS which frame to show
/// for the sun's position (solar) or the system light/dark appearance.
enum DynamicHEICBuilder {

    enum BuildError: Error { case noImages, encode, metadata }

    /// One frame mapped to a sun position (degrees).
    struct SolarFrame {
        let image: URL
        let altitude: Double   // sun elevation, negative = night
        let azimuth: Double    // compass bearing
    }

    /// Light/dark wallpaper from exactly two images.
    static func buildLightDark(light: URL, dark: URL, to dest: URL) throws {
        let plist: [String: Any] = ["l": 0, "d": 1]
        try write(images: [light, dark],
                  tag: "apr",
                  plist: plist,
                  to: dest)
    }

    /// Solar wallpaper: frames ordered as supplied, each pinned to a sun position.
    static func buildSolar(frames: [SolarFrame], lightIndex: Int, darkIndex: Int, to dest: URL) throws {
        guard !frames.isEmpty else { throw BuildError.noImages }
        let si = frames.enumerated().map { idx, f in
            ["a": f.altitude, "z": f.azimuth, "i": idx] as [String: Any]
        }
        let plist: [String: Any] = [
            "ap": ["l": lightIndex, "d": darkIndex],
            "si": si
        ]
        try write(images: frames.map(\.image), tag: "solar", plist: plist, to: dest)
    }

    // MARK: - Core HEIC writer

    private static func write(images: [URL], tag: String, plist: [String: Any], to dest: URL) throws {
        guard !images.isEmpty else { throw BuildError.noImages }

        // Serialize the dynamic descriptor as a binary plist, then base64 — the
        // exact encoding macOS expects in the apple_desktop metadata value.
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let base64 = data.base64EncodedString()

        let meta = CGImageMetadataCreateMutable()
        var err: Unmanaged<CFError>?
        let ns = "http://ns.apple.com/namespace/1.0/"
        guard CGImageMetadataRegisterNamespaceForPrefix(meta, ns as CFString, "apple_desktop" as CFString, &err) else {
            throw BuildError.metadata
        }
        guard CGImageMetadataSetValueWithPath(meta, nil, "apple_desktop:\(tag)" as CFString, base64 as CFString) else {
            throw BuildError.metadata
        }

        try? FileManager.default.removeItem(at: dest)
        guard let destination = CGImageDestinationCreateWithURL(
            dest as CFURL, UTType.heic.identifier as CFString, images.count, nil) else {
            throw BuildError.encode
        }

        for (idx, url) in images.enumerated() {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                throw BuildError.encode
            }
            if idx == 0 {
                // Only the primary image carries the dynamic metadata.
                CGImageDestinationAddImageAndMetadata(destination, cg, meta, nil)
            } else {
                CGImageDestinationAddImage(destination, cg, nil)
            }
        }

        guard CGImageDestinationFinalize(destination) else { throw BuildError.encode }
    }
}
