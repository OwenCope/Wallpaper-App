import SceneKit
import AppKit

enum HeldItem: String, CaseIterable, Identifiable {
    case none = "None", sword = "Sword"
    var id: String { rawValue }
}

enum Armor: String, CaseIterable, Identifiable {
    case none = "None", leather = "Leather", chainmail = "Chainmail"
    case iron = "Iron", gold = "Gold", diamond = "Diamond", netherite = "Netherite"
    var id: String { rawValue }

    var color: NSColor? {
        switch self {
        case .none:      nil
        case .leather:   NSColor(red: 0.55, green: 0.33, blue: 0.18, alpha: 1)
        case .chainmail: NSColor(white: 0.55, alpha: 1)
        case .iron:      NSColor(white: 0.82, alpha: 1)
        case .gold:      NSColor(red: 0.95, green: 0.80, blue: 0.25, alpha: 1)
        case .diamond:   NSColor(red: 0.40, green: 0.85, blue: 0.85, alpha: 1)
        case .netherite: NSColor(red: 0.22, green: 0.19, blue: 0.20, alpha: 1)
        }
    }

    /// Equipment texture basename.
    var file: String? {
        switch self {
        case .none: nil
        case .leather: "leather"
        case .chainmail: "chainmail"
        case .iron: "iron"
        case .gold: "gold"
        case .diamond: "diamond"
        case .netherite: "netherite"
        }
    }

    /// Matching sword tier for the held weapon.
    var swordTier: String {
        switch self {
        case .none, .iron: "iron"
        case .leather: "wooden"
        case .chainmail: "stone"
        case .gold: "golden"
        case .diamond: "diamond"
        case .netherite: "netherite"
        }
    }
}

enum TrimPattern: String, CaseIterable, Identifiable {
    case none, coast, sentry, dune, wild, ward, eye, vex, tide, snout
    case rib, spire, wayfinder, shaper, silence, raiser, host, flow, bolt
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum TrimMaterial: String, CaseIterable, Identifiable {
    case quartz, iron, gold, lapis, emerald, diamond, netherite, redstone, copper, amethyst, resin
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Recolors a greyscale trim texture using Minecraft's palette-key → material-palette mapping.
enum TrimRecolor {
    static func apply(_ trim: CGImage, key: CGImage, palette: CGImage) -> CGImage? {
        let keyColors = colors(of: key), palColors = colors(of: palette)
        guard !keyColors.isEmpty, keyColors.count == palColors.count else { return nil }
        let w = trim.width, h = trim.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(trim, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] > 0 {
            let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
            var best = 0, bestDist = Int.max
            for (idx, k) in keyColors.enumerated() {
                let d = (r - Int(k.0)) * (r - Int(k.0)) + (g - Int(k.1)) * (g - Int(k.1)) + (b - Int(k.2)) * (b - Int(k.2))
                if d < bestDist { bestDist = d; best = idx }
            }
            let p = palColors[best]
            data[i] = p.0; data[i + 1] = p.1; data[i + 2] = p.2
        }
        return ctx.makeImage()
    }

    private static func colors(of img: CGImage) -> [(UInt8, UInt8, UInt8)] {
        let w = img.width, h = img.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (0..<w).map { (data[$0 * 4], data[$0 * 4 + 1], data[$0 * 4 + 2]) }
    }
}

/// Builds a small preview image of a trim composited onto the armor (chestplate front).
enum ArmorTrimSwatch {
    static func make(armor: CGImage?, trim: CGImage?, tint: NSColor? = nil) -> NSImage? {
        guard let armor else { return nil }
        let w = armor.width, h = armor.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(armor, in: full)
        if let tint {   // dye greyscale leather
            ctx.setBlendMode(.multiply); ctx.setFillColor(tint.cgColor); ctx.fill(full)
            ctx.setBlendMode(.normal)
        }
        if let trim { ctx.draw(trim, in: full) }
        guard let composed = ctx.makeImage() else { return nil }
        // Crop the chestplate front face (x16–28, y20–32 on a 64-wide texture)
        // — the body front plus a sliver of shoulder so it reads as a chestplate.
        let s = CGFloat(w) / 64
        let rect = CGRect(x: 20 * s, y: 20 * s, width: 8 * s, height: 12 * s)
        guard let crop = composed.cropping(to: rect) else { return nil }
        return NSImage(cgImage: crop, size: NSSize(width: 8, height: 12))
    }
}

/// Fetches real Minecraft textures (armor equipment + item icons), cached.
/// An actor so the cache is never mutated from two concurrent tasks at once.
actor TextureService {
    static let shared = TextureService()
    private var cache: [String: CGImage] = [:]
    private let base = "https://raw.githubusercontent.com/misode/mcmeta/assets/assets/minecraft/textures"

    /// (layer_1 = helmet/chest/boots, layer_2 = leggings)
    func armor(_ armor: Armor) async -> (CGImage?, CGImage?) {
        guard let f = armor.file else { return (nil, nil) }
        let l1 = await tex("entity/equipment/humanoid/\(f)")
        let l2 = await tex("entity/equipment/humanoid_leggings/\(f)")
        return (l1, l2)
    }

    func sword(_ armor: Armor) async -> CGImage? { await tex("item/\(armor.swordTier)_sword") }

    /// Recolored trim overlays (body, leggings) for a pattern + material.
    func trim(_ pattern: TrimPattern, _ material: TrimMaterial) async -> (CGImage?, CGImage?) {
        guard pattern != .none else { return (nil, nil) }
        let key = await tex("trims/color_palettes/trim_palette")
        let pal = await tex("trims/color_palettes/\(material.rawValue)")
        let body = await tex("trims/entity/humanoid/\(pattern.rawValue)")
        let legs = await tex("trims/entity/humanoid_leggings/\(pattern.rawValue)")
        guard let key, let pal else { return (nil, nil) }
        return (body.flatMap { TrimRecolor.apply($0, key: key, palette: pal) },
                legs.flatMap { TrimRecolor.apply($0, key: key, palette: pal) })
    }

    private func tex(_ path: String) async -> CGImage? {
        if let cached = cache[path] { return cached }
        guard let url = URL(string: "\(base)/\(path).png"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        cache[path] = cg
        return cg
    }
}

enum Biome: String, CaseIterable, Identifiable {
    case plains = "Plains", desert = "Desert", snow = "Snow"
    case nether = "Nether", ocean = "Ocean", end = "End"
    var id: String { rawValue }

    /// Accurate Wallhaven search query for a real backdrop image.
    var query: String {
        switch self {
        case .plains: "minecraft plains landscape"
        case .desert: "minecraft desert"
        case .snow:   "minecraft snowy"
        case .nether: "minecraft nether"
        case .ocean:  "minecraft ocean"
        case .end:    "minecraft the end"
        }
    }

    struct Palette {
        let skyTop: NSColor
        let skyHorizon: NSColor
        let ground: NSColor
        let groundShade: NSColor
        let sun: NSColor?       // nil = no sun (e.g. Nether)
    }

    var palette: Palette {
        switch self {
        case .plains: Palette(skyTop: rgb(0.30, 0.55, 0.95), skyHorizon: rgb(0.74, 0.86, 0.98),
                              ground: rgb(0.42, 0.66, 0.28), groundShade: rgb(0.30, 0.50, 0.20), sun: rgb(1, 0.96, 0.7))
        case .desert: Palette(skyTop: rgb(0.42, 0.66, 0.95), skyHorizon: rgb(0.85, 0.88, 0.92),
                              ground: rgb(0.86, 0.76, 0.48), groundShade: rgb(0.74, 0.62, 0.36), sun: rgb(1, 0.98, 0.8))
        case .snow:   Palette(skyTop: rgb(0.62, 0.76, 0.92), skyHorizon: rgb(0.88, 0.93, 0.98),
                              ground: rgb(0.92, 0.95, 0.98), groundShade: rgb(0.80, 0.86, 0.93), sun: rgb(1, 1, 0.95))
        case .nether: Palette(skyTop: rgb(0.30, 0.04, 0.04), skyHorizon: rgb(0.55, 0.12, 0.06),
                              ground: rgb(0.32, 0.06, 0.05), groundShade: rgb(0.18, 0.03, 0.03), sun: nil)
        case .ocean:  Palette(skyTop: rgb(0.30, 0.55, 0.85), skyHorizon: rgb(0.70, 0.85, 0.95),
                              ground: rgb(0.12, 0.38, 0.62), groundShade: rgb(0.06, 0.22, 0.42), sun: rgb(1, 0.97, 0.78))
        case .end:    Palette(skyTop: rgb(0.06, 0.04, 0.10), skyHorizon: rgb(0.16, 0.12, 0.22),
                              ground: rgb(0.86, 0.86, 0.70), groundShade: rgb(0.66, 0.66, 0.52), sun: nil)
        }
    }

    private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(red: r, green: g, blue: b, alpha: 1)
    }
}

/// Builds the SceneKit scene for a Minecraft character.
enum MinecraftModel {

    /// A box face crop, in skin-pixel coordinates (top-left origin).
    private struct Face { let x, y, w, h: Int }

    static func scene(skins: [NSImage], item: HeldItem, biome: Biome,
                      armorLayer1: CGImage? = nil, armorLayer2: CGImage? = nil,
                      swordTexture: CGImage? = nil,
                      helmetTrim: CGImage? = nil, chestTrim: CGImage? = nil,
                      leggingsTrim: CGImage? = nil, bootsTrim: CGImage? = nil,
                      enchanted: Bool = false, armorTint: NSColor? = nil,
                      rotations: [Double] = []) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = backgroundImage(for: biome)

        for (index, skin) in skins.enumerated() {
        guard let cg = skin.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
        // Modern skins are square (64×64); legacy are 64×32 (height < width).
        let legacy = cg.height < cg.width

        let container = SCNNode()
        container.name = "player\(index)"

        // Order for SCNBox materials: front(+Z), right(+X), back(-Z), left(-X), top(+Y), bottom(-Y).
        // Head
        let head = box(8, 8, 8, faces: [
            Face(x: 8, y: 8, w: 8, h: 8),   Face(x: 16, y: 8, w: 8, h: 8),
            Face(x: 24, y: 8, w: 8, h: 8),  Face(x: 0, y: 8, w: 8, h: 8),
            Face(x: 8, y: 0, w: 8, h: 8),   Face(x: 16, y: 0, w: 8, h: 8),
        ], cg: cg)
        head.position = SCNVector3(0, 10, 0)
        container.addChildNode(head)

        // Body
        let body = box(8, 12, 4, faces: [
            Face(x: 20, y: 20, w: 8, h: 12), Face(x: 28, y: 20, w: 4, h: 12),
            Face(x: 32, y: 20, w: 8, h: 12), Face(x: 16, y: 20, w: 4, h: 12),
            Face(x: 20, y: 16, w: 8, h: 4),  Face(x: 28, y: 16, w: 8, h: 4),
        ], cg: cg)
        body.position = SCNVector3(0, 0, 0)
        container.addChildNode(body)

        // Right arm
        let rightArm = box(4, 12, 4, faces: [
            Face(x: 44, y: 20, w: 4, h: 12), Face(x: 48, y: 20, w: 4, h: 12),
            Face(x: 52, y: 20, w: 4, h: 12), Face(x: 40, y: 20, w: 4, h: 12),
            Face(x: 44, y: 16, w: 4, h: 4),  Face(x: 48, y: 16, w: 4, h: 4),
        ], cg: cg)
        rightArm.position = SCNVector3(-6, 0, 0)
        container.addChildNode(rightArm)

        // Left arm (falls back to right-arm texture on legacy skins)
        let la: [Face] = legacy
            ? [Face(x: 44, y: 20, w: 4, h: 12), Face(x: 48, y: 20, w: 4, h: 12),
               Face(x: 52, y: 20, w: 4, h: 12), Face(x: 40, y: 20, w: 4, h: 12),
               Face(x: 44, y: 16, w: 4, h: 4),  Face(x: 48, y: 16, w: 4, h: 4)]
            : [Face(x: 36, y: 52, w: 4, h: 12), Face(x: 40, y: 52, w: 4, h: 12),
               Face(x: 44, y: 52, w: 4, h: 12), Face(x: 32, y: 52, w: 4, h: 12),
               Face(x: 36, y: 48, w: 4, h: 4),  Face(x: 40, y: 48, w: 4, h: 4)]
        let leftArm = box(4, 12, 4, faces: la, cg: cg)
        leftArm.position = SCNVector3(6, 0, 0)
        container.addChildNode(leftArm)

        // Right leg
        let rightLeg = box(4, 12, 4, faces: [
            Face(x: 4, y: 20, w: 4, h: 12), Face(x: 8, y: 20, w: 4, h: 12),
            Face(x: 12, y: 20, w: 4, h: 12), Face(x: 0, y: 20, w: 4, h: 12),
            Face(x: 4, y: 16, w: 4, h: 4),  Face(x: 8, y: 16, w: 4, h: 4),
        ], cg: cg)
        rightLeg.position = SCNVector3(-2, -12, 0)
        container.addChildNode(rightLeg)

        // Left leg
        let ll: [Face] = legacy
            ? [Face(x: 4, y: 20, w: 4, h: 12), Face(x: 8, y: 20, w: 4, h: 12),
               Face(x: 12, y: 20, w: 4, h: 12), Face(x: 0, y: 20, w: 4, h: 12),
               Face(x: 4, y: 16, w: 4, h: 4),  Face(x: 8, y: 16, w: 4, h: 4)]
            : [Face(x: 20, y: 52, w: 4, h: 12), Face(x: 24, y: 52, w: 4, h: 12),
               Face(x: 28, y: 52, w: 4, h: 12), Face(x: 16, y: 52, w: 4, h: 12),
               Face(x: 20, y: 48, w: 4, h: 4),  Face(x: 24, y: 48, w: 4, h: 4)]
        let leftLeg = box(4, 12, 4, faces: ll, cg: cg)
        leftLeg.position = SCNVector3(2, -12, 0)
        container.addChildNode(leftLeg)

        // ---- Second skin layer (overlays) ----
        // Hat layer exists even on legacy 64×32 skins.
        addOverlay(container, 8, 8, 8, at: head.position, faces: [
            Face(x: 40, y: 8, w: 8, h: 8), Face(x: 48, y: 8, w: 8, h: 8),
            Face(x: 56, y: 8, w: 8, h: 8), Face(x: 32, y: 8, w: 8, h: 8),
            Face(x: 40, y: 0, w: 8, h: 8), Face(x: 48, y: 0, w: 8, h: 8),
        ], cg: cg)

        if !legacy {
            // Jacket (body)
            addOverlay(container, 8, 12, 4, at: body.position, faces: [
                Face(x: 20, y: 36, w: 8, h: 12), Face(x: 28, y: 36, w: 4, h: 12),
                Face(x: 32, y: 36, w: 8, h: 12), Face(x: 16, y: 36, w: 4, h: 12),
                Face(x: 20, y: 32, w: 8, h: 4),  Face(x: 28, y: 32, w: 8, h: 4),
            ], cg: cg)
            // Right sleeve
            addOverlay(container, 4, 12, 4, at: rightArm.position, faces: [
                Face(x: 44, y: 36, w: 4, h: 12), Face(x: 48, y: 36, w: 4, h: 12),
                Face(x: 52, y: 36, w: 4, h: 12), Face(x: 40, y: 36, w: 4, h: 12),
                Face(x: 44, y: 32, w: 4, h: 4),  Face(x: 48, y: 32, w: 4, h: 4),
            ], cg: cg)
            // Left sleeve
            addOverlay(container, 4, 12, 4, at: leftArm.position, faces: [
                Face(x: 52, y: 52, w: 4, h: 12), Face(x: 56, y: 52, w: 4, h: 12),
                Face(x: 60, y: 52, w: 4, h: 12), Face(x: 48, y: 52, w: 4, h: 12),
                Face(x: 52, y: 48, w: 4, h: 4),  Face(x: 56, y: 48, w: 4, h: 4),
            ], cg: cg)
            // Right pant
            addOverlay(container, 4, 12, 4, at: rightLeg.position, faces: [
                Face(x: 4, y: 36, w: 4, h: 12), Face(x: 8, y: 36, w: 4, h: 12),
                Face(x: 12, y: 36, w: 4, h: 12), Face(x: 0, y: 36, w: 4, h: 12),
                Face(x: 4, y: 32, w: 4, h: 4),  Face(x: 8, y: 32, w: 4, h: 4),
            ], cg: cg)
            // Left pant
            addOverlay(container, 4, 12, 4, at: leftLeg.position, faces: [
                Face(x: 4, y: 52, w: 4, h: 12), Face(x: 8, y: 52, w: 4, h: 12),
                Face(x: 12, y: 52, w: 4, h: 12), Face(x: 0, y: 52, w: 4, h: 12),
                Face(x: 4, y: 48, w: 4, h: 4),  Face(x: 8, y: 48, w: 4, h: 4),
            ], cg: cg)
        }

        // ---- Armor (real Minecraft armor textures, applied as inflated layers) ----
        // Armor textures use the legacy 64×32 UV layout (same regions as the base skin).
        let headFaces = [
            Face(x: 8, y: 8, w: 8, h: 8), Face(x: 16, y: 8, w: 8, h: 8),
            Face(x: 24, y: 8, w: 8, h: 8), Face(x: 0, y: 8, w: 8, h: 8),
            Face(x: 8, y: 0, w: 8, h: 8), Face(x: 16, y: 0, w: 8, h: 8),
        ]
        let bodyFaces = [
            Face(x: 20, y: 20, w: 8, h: 12), Face(x: 28, y: 20, w: 4, h: 12),
            Face(x: 32, y: 20, w: 8, h: 12), Face(x: 16, y: 20, w: 4, h: 12),
            Face(x: 20, y: 16, w: 8, h: 4),  Face(x: 28, y: 16, w: 8, h: 4),
        ]
        let armFaces = [
            Face(x: 44, y: 20, w: 4, h: 12), Face(x: 48, y: 20, w: 4, h: 12),
            Face(x: 52, y: 20, w: 4, h: 12), Face(x: 40, y: 20, w: 4, h: 12),
            Face(x: 44, y: 16, w: 4, h: 4),  Face(x: 48, y: 16, w: 4, h: 4),
        ]
        let legFaces = [
            Face(x: 4, y: 20, w: 4, h: 12), Face(x: 8, y: 20, w: 4, h: 12),
            Face(x: 12, y: 20, w: 4, h: 12), Face(x: 0, y: 20, w: 4, h: 12),
            Face(x: 4, y: 16, w: 4, h: 4),  Face(x: 8, y: 16, w: 4, h: 4),
        ]
        // Layers stack inside-out by inflate; renderingOrder must match (no depth writes).
        // leggings armor(0.6,o2) < leggings trim(0.82,o3) < layer1 armor(1.0-1.1,o4) < trims(1.1+,o5)
        // layer_2: leggings (innermost).
        if let a2 = armorLayer2 {
            addArmor(container, 4, 12, 4, inflate: 0.6, at: rightLeg.position, faces: legFaces, cg: a2, glow: enchanted, order: 2, tint: armorTint)
            addArmor(container, 4, 12, 4, inflate: 0.6, at: leftLeg.position, faces: legFaces, cg: a2, glow: enchanted, order: 2, tint: armorTint)
        }
        if let t = leggingsTrim {
            addArmor(container, 4, 12, 4, inflate: 0.66, at: rightLeg.position, faces: legFaces, cg: t, glow: false, order: 3)
            addArmor(container, 4, 12, 4, inflate: 0.66, at: leftLeg.position, faces: legFaces, cg: t, glow: false, order: 3)
        }
        // layer_1: helmet, chestplate, sleeves, boots.
        if let a1 = armorLayer1 {
            addArmor(container, 8, 8, 8, inflate: 1.1, at: head.position, faces: headFaces, cg: a1, glow: enchanted, order: 4, tint: armorTint)
            addArmor(container, 8, 12, 4, inflate: 1.0, at: body.position, faces: bodyFaces, cg: a1, glow: enchanted, order: 4, tint: armorTint)
            addArmor(container, 4, 12, 4, inflate: 1.0, at: rightArm.position, faces: armFaces, cg: a1, glow: enchanted, order: 4, tint: armorTint)
            addArmor(container, 4, 12, 4, inflate: 1.0, at: leftArm.position, faces: armFaces, cg: a1, glow: enchanted, order: 4, tint: armorTint)
            addArmor(container, 4, 12, 4, inflate: 1.1, at: rightLeg.position, faces: legFaces, cg: a1, glow: enchanted, order: 4, tint: armorTint)
            addArmor(container, 4, 12, 4, inflate: 1.1, at: leftLeg.position, faces: legFaces, cg: a1, glow: enchanted, order: 4, tint: armorTint)
        }
        // Per-piece trims (outermost).
        if let t = helmetTrim {
            addArmor(container, 8, 8, 8, inflate: 1.16, at: head.position, faces: headFaces, cg: t, glow: false, order: 5)
        }
        if let t = chestTrim {
            addArmor(container, 8, 12, 4, inflate: 1.06, at: body.position, faces: bodyFaces, cg: t, glow: false, order: 5)
            addArmor(container, 4, 12, 4, inflate: 1.06, at: rightArm.position, faces: armFaces, cg: t, glow: false, order: 5)
            addArmor(container, 4, 12, 4, inflate: 1.06, at: leftArm.position, faces: armFaces, cg: t, glow: false, order: 5)
        }
        if let t = bootsTrim {
            addArmor(container, 4, 12, 4, inflate: 1.16, at: rightLeg.position, faces: legFaces, cg: t, glow: false, order: 5)
            addArmor(container, 4, 12, 4, inflate: 1.16, at: leftLeg.position, faces: legFaces, cg: t, glow: false, order: 5)
        }

        // Held item attaches to the right hand (child of the arm, so it moves with it).
        if item == .sword, let swordTexture {
            // Real Minecraft sword extruded pixel-by-pixel into a true 3D item.
            let node = swordModel(from: swordTexture, enchanted: enchanted)
            // Sideways, blade up-and-forward, handle in the fist.
            node.position = SCNVector3(0, -0.5, 6)
            node.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
            rightArm.addChildNode(node)
        }

        // Position characters side by side, centered around the origin.
        let spacing: Float = 16
        let x = (Float(index) - Float(skins.count - 1) / 2) * spacing
        container.position = SCNVector3(x, 1, 0)
        // Individual rotation (degrees → radians) about the character's own axis.
        if index < rotations.count {
            container.eulerAngles.y = CGFloat(rotations[index]) * .pi / 180
        }
        scene.rootNode.addChildNode(container)
        }   // end per-skin loop

        // Camera.
        let camera = SCNCamera()
        camera.fieldOfView = 55
        camera.zNear = 1
        camera.zFar = 2000     // default 100 clips characters once the camera pulls back for 4+ players
        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 62 + CGFloat(max(0, skins.count - 1)) * 16)
        scene.rootNode.addChildNode(cameraNode)

        // Light (only affects armor; skin uses .constant so it stays flat & true-colored).
        let light = SCNLight()
        light.type = .directional
        light.intensity = 900
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 5, 0)
        scene.rootNode.addChildNode(lightNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 500
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        return scene
    }

    // MARK: - Armor helpers

    /// Add an inflated, textured armor layer over a base part.
    private static func addArmor(_ parent: SCNNode, _ w: CGFloat, _ h: CGFloat, _ d: CGFloat,
                                 inflate: CGFloat, at position: SCNVector3, faces: [Face], cg: CGImage,
                                 glow: Bool = true, order: Int = 2, tint: NSColor? = nil) {
        let node = box(w + inflate, h + inflate, d + inflate, faces: faces, cg: cg, transparent: true)
        node.position = position
        node.renderingOrder = order
        if let tint {   // greyscale leather is dyed by multiplying with its colour
            node.geometry?.materials.forEach { $0.multiply.contents = tint }
        }
        if glow {
            // Faint purple enchant sheen (masked by the texture's alpha).
            node.geometry?.materials.forEach { mat in
                mat.emission.contents = NSColor(red: 0.55, green: 0.20, blue: 0.95, alpha: 1)
                mat.emission.intensity = 0.15
            }
        }
        parent.addChildNode(node)
    }

    // MARK: - Geometry helpers

    private static func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, faces: [Face], cg: CGImage, transparent: Bool = false) -> SCNNode {
        let geo = SCNBox(width: w, height: h, length: d, chamferRadius: 0)
        geo.materials = faces.map { material(crop: $0, cg: cg, transparent: transparent) }
        return SCNNode(geometry: geo)
    }

    private static func material(crop: Face, cg: CGImage, transparent: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        // Skin coordinates assume a 64-wide texture; scale to the real pixel size.
        let scale = CGFloat(cg.width) / 64.0
        let rect = CGRect(x: CGFloat(crop.x) * scale, y: CGFloat(crop.y) * scale,
                          width: CGFloat(crop.w) * scale, height: CGFloat(crop.h) * scale)
        if let sub = cg.cropping(to: rect) {
            m.diffuse.contents = NSImage(cgImage: sub, size: NSSize(width: crop.w, height: crop.h))
        } else {
            m.diffuse.contents = transparent ? NSColor.clear : NSColor.systemGray
        }
        m.diffuse.magnificationFilter = .nearest
        m.diffuse.minificationFilter = .nearest
        m.lightingModel = .constant   // flat, full-brightness pixels
        m.isDoubleSided = true
        if transparent {
            // Second skin layer: cut out where the texture is transparent.
            m.transparencyMode = .aOne
            m.blendMode = .alpha
            m.writesToDepthBuffer = false
        }
        return m
    }

    /// Add a slightly-larger transparent "second layer" box over a base part.
    private static func addOverlay(_ parent: SCNNode, _ w: CGFloat, _ h: CGFloat, _ d: CGFloat,
                                   at position: SCNVector3, faces: [Face], cg: CGImage) {
        let node = box(w + 0.5, h + 0.5, d + 0.5, faces: faces, cg: cg, transparent: true)
        node.position = position
        node.renderingOrder = 1   // draw after the base layer
        parent.addChildNode(node)
    }

    /// Extrudes a 16×16 item texture into a real 3D pixel model (like Minecraft held items).
    private static func swordModel(from cg: CGImage, enchanted: Bool) -> SCNNode {
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let parent = SCNNode()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return parent }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        let px: CGFloat = 0.9, depth: CGFloat = 1.4
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                guard data[i + 3] > 20 else { continue }
                let box = SCNBox(width: px, height: px, length: depth, chamferRadius: 0)
                let m = SCNMaterial()
                m.diffuse.contents = NSColor(srgbRed: CGFloat(data[i]) / 255, green: CGFloat(data[i + 1]) / 255,
                                             blue: CGFloat(data[i + 2]) / 255, alpha: 1)
                m.lightingModel = .blinn
                if enchanted {
                    m.emission.contents = NSColor(red: 0.55, green: 0.20, blue: 0.95, alpha: 1)
                    m.emission.intensity = 0.15
                }
                box.firstMaterial = m
                let node = SCNNode(geometry: box)
                node.position = SCNVector3((CGFloat(x) - CGFloat(w) / 2 + 0.5) * px,
                                           (CGFloat(h - 1 - y) - CGFloat(h) / 2 + 0.5) * px, 0)
                parent.addChildNode(node)
            }
        }
        return parent.flattenedClone()   // merge into few draw calls
    }

    // MARK: - Held items (stylized primitives)

    // MARK: - Biome backdrop

    /// Draws a simple blocky biome scene: sky gradient, sun, and a layered horizon.
    static func backgroundImage(for biome: Biome) -> NSImage {
        let p = biome.palette
        let size = NSSize(width: 1600, height: 1000)
        let horizon = size.height * 0.40   // ground occupies bottom 40%
        let image = NSImage(size: size)
        image.lockFocus()

        // Sky gradient (top → horizon).
        if let sky = NSGradient(colors: [p.skyTop, p.skyHorizon].compactMap { $0.usingColorSpace(.sRGB) }) {
            sky.draw(in: NSRect(x: 0, y: horizon, width: size.width, height: size.height - horizon), angle: -90)
        }

        // Sun/moon as a soft blocky square.
        if let sun = p.sun {
            sun.setFill()
            let s: CGFloat = 120
            NSRect(x: size.width * 0.72, y: size.height * 0.72, width: s, height: s).fill()
        }

        // Ground band with a slightly darker base strip for depth.
        p.ground.setFill()
        NSRect(x: 0, y: 0, width: size.width, height: horizon).fill()
        p.groundShade.setFill()
        NSRect(x: 0, y: 0, width: size.width, height: horizon * 0.45).fill()

        // A few blocky hills on the horizon for a scene feel.
        p.groundShade.withAlphaComponent(0.9).setFill()
        for i in 0..<6 {
            let w = size.width / 6
            let h = horizon * (0.15 + 0.12 * CGFloat((i * 37 % 5)))
            NSRect(x: CGFloat(i) * w, y: horizon - 1, width: w, height: h).fill()
        }

        image.unlockFocus()
        return image
    }
}
