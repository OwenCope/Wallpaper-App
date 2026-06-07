import SwiftUI
import SceneKit
import ImageIO

/// Decodes a downsampled image off the main thread to keep the UI smooth.
enum ImageDownsampler {
    static func image(from data: Data, maxPixel: CGFloat) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

// MARK: - API render service

enum SkinRenderService {
    enum Pose: String, CaseIterable, Identifiable {
        case `default` = "Default", isometric = "Isometric", marching = "Marching"
        case walking = "Walking", crouching = "Crouching", pointing = "Pointing"
        case lunging = "Lunging", cheering = "Cheering", archer = "Archer"
        case relaxing = "Relaxing", trudging = "Trudging", kicking = "Kicking"
        case reading = "Reading", mojavatar = "Mojavatar", ultimate = "Ultimate"
        var id: String { rawValue }
        var api: String { rawValue.lowercased() }
    }
    enum RenderView: String, CaseIterable, Identifiable {
        case full = "Full body", bust = "Bust", face = "Face"
        var id: String { rawValue }
        var api: String { switch self { case .full: "full"; case .bust: "bust"; case .face: "face" } }
    }

    static func render(username: String, pose: Pose, view: RenderView) async -> NSImage? {
        // 1. Try the high-quality Starlight render in the chosen pose.
        if let img = await fetch(username: username, pose: pose.api, view: view.api) { return img }
        // 2. Fall back to Starlight's default pose.
        if pose != .default, let img = await fetch(username: username, pose: "default", view: view.api) { return img }
        // 3. Last resort: mc-heads (very reliable, username-based body render).
        return await mcHeads(username: username)
    }

    private static func mcHeads(username: String) async -> NSImage? {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "https://mc-heads.net/body/\(name)/512") else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let image = NSImage(data: data) else { return nil }
        return image
    }

    private static func fetch(username: String, pose: String, view: String) async -> NSImage? {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              let url = URL(string: "https://starlightskins.lunareclipse.studio/render/\(pose)/\(name)/\(view)")
        else { return nil }
        for attempt in 0..<3 {
            if let (data, response) = try? await URLSession.shared.data(from: url),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let image = NSImage(data: data) { return image }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 500_000_000) }
        }
        return nil
    }
}

// MARK: - 3D scene host

/// SCNView that lets you click+drag an individual character to spin it in place.
final class InteractiveSCNView: SCNView {
    /// Persisted per-character rotation in degrees (survives scene rebuilds).
    var yaws: [Int: Double] = [:]
    private var draggedIndex: Int?
    var baseCameraZ: CGFloat = 62
    var zoomOffset: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        // With 1 player, SceneKit's camera control handles zoom (old behavior).
        if allowsCameraControl { super.scrollWheel(with: event); return }
        zoomOffset = min(max(zoomOffset - CGFloat(event.scrollingDeltaY) * 0.6, -40), 240)
        applyZoom()
    }
    func applyZoom() {
        pointOfView?.position.z = baseCameraZ + zoomOffset
    }

    override func mouseDown(with event: NSEvent) {
        if allowsCameraControl { super.mouseDown(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        draggedIndex = hitTest(p, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            .lazy.compactMap { self.playerIndex(of: $0.node) }.first
        if draggedIndex == nil { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        if allowsCameraControl { super.mouseDragged(with: event); return }
        guard let i = draggedIndex else { super.mouseDragged(with: event); return }
        yaws[i, default: 0] += Double(event.deltaX) * 0.6
        applyYaw(i)
    }

    private func applyYaw(_ i: Int) {
        guard let node = scene?.rootNode.childNode(withName: "player\(i)", recursively: false) else { return }
        node.eulerAngles.y = CGFloat(yaws[i] ?? 0) * .pi / 180
    }

    /// Re-apply stored rotations after a scene rebuild.
    func reapplyYaws() { yaws.keys.forEach(applyYaw) }

    private func playerIndex(of node: SCNNode) -> Int? {
        var n: SCNNode? = node
        while let cur = n {
            if let name = cur.name, name.hasPrefix("player"), let idx = Int(name.dropFirst(6)) { return idx }
            n = cur.parent
        }
        return nil
    }
}

@MainActor
final class SceneController: ObservableObject {
    let scnView: InteractiveSCNView = {
        let v = InteractiveSCNView()
        v.allowsCameraControl = false   // we drive rotation per-character instead
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = .black
        v.autoenablesDefaultLighting = false
        return v
    }()
    func rebuild(skins: [NSImage], item: HeldItem, biome: Biome,
                 armorLayer1: CGImage?, armorLayer2: CGImage?, swordTexture: CGImage?,
                 helmetTrim: CGImage?, chestTrim: CGImage?, leggingsTrim: CGImage?, bootsTrim: CGImage?,
                 enchanted: Bool, armorTint: NSColor?) {
        // 1 player → free camera orbit (old feel); multiple → per-character drag.
        scnView.allowsCameraControl = skins.count <= 1
        let rotations = (0..<skins.count).map { scnView.yaws[$0] ?? 0 }
        scnView.scene = MinecraftModel.scene(skins: skins, item: item, biome: biome,
                                             armorLayer1: armorLayer1, armorLayer2: armorLayer2,
                                             swordTexture: swordTexture,
                                             helmetTrim: helmetTrim, chestTrim: chestTrim,
                                             leggingsTrim: leggingsTrim, bootsTrim: bootsTrim,
                                             enchanted: enchanted, armorTint: armorTint, rotations: rotations)
        // Point the view at our scene camera (avoids a stale/detached camera → black screen).
        scnView.pointOfView = scnView.scene?.rootNode.childNode(withName: "camera", recursively: false)
        // Preserve zoom across rebuilds.
        scnView.baseCameraZ = scnView.pointOfView?.position.z ?? 62
        scnView.applyZoom()
    }
    func setBackground(_ image: NSImage) { scnView.scene?.background.contents = image }
    func setBackgroundBlack() { scnView.scene?.background.contents = NSColor.black }
    func snapshot() -> NSImage { scnView.snapshot() }
}

private struct SceneKitView: NSViewRepresentable {
    let controller: SceneController
    func makeNSView(context: Context) -> InteractiveSCNView { controller.scnView }
    func updateNSView(_ nsView: InteractiveSCNView, context: Context) {}
}

// MARK: - View

enum ArmorPiece: String, CaseIterable, Identifiable {
    case helmet = "Helmet", chest = "Chestplate", leggings = "Leggings", boots = "Boots"
    var id: String { rawValue }
}

struct PieceTrim: Equatable {
    var pattern: TrimPattern = .none
    var material: TrimMaterial = .gold
}

struct Player: Identifiable {
    let id = UUID()
    let name: String
    let skin: NSImage
    var yaw: Double = 0   // degrees, individual rotation
}

struct MinecraftView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case render = "2D Render", threeD = "3D Rotate"
        var id: String { rawValue }
    }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rotation: RotationManager
    @AppStorage("wallhaven.apiKey") private var apiKey = ""
    @StateObject private var controller = SceneController()

    @State private var mode: Mode = .render
    @State private var username = ""
    @State private var pose: SkinRenderService.Pose = .default
    @State private var renderView: SkinRenderService.RenderView = .full
    @State private var item: HeldItem = .none
    @State private var armor: Armor = .none
    @State private var trims: [ArmorPiece: PieceTrim] = [
        .helmet: .init(), .chest: .init(), .leggings: .init(), .boots: .init()]
    @State private var matchAll = true
    @State private var allTrim = PieceTrim()
    @State private var trimSwatches: [String: NSImage] = [:]
    @State private var enchanted = false
    @State private var biome: Biome = .plains

    @State private var character: NSImage?    // 2D render
    @State private var skinImage: NSImage?     // raw skin for 3D (most recent)
    @State private var players: [Player] = []  // multiple characters in 3D
    @State private var background: NSImage?
    @State private var backgrounds: [WallhavenPhoto] = []
    @State private var selectedBgID: String?
    @State private var blackBg = true
    @State private var thumbCache: [String: NSImage] = [:]
    @State private var characterScale: Double = 0.85

    @State private var loading = false
    @State private var loadingBg = false
    @State private var error: String?
    @State private var status: String?

    private var bgService: WallhavenService { WallhavenService(apiKey: apiKey.isEmpty ? nil : apiKey) }
    private var hasContent: Bool { mode == .render ? character != nil : !players.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            stage.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 70)
        .onChange(of: mode) { _, _ in Task { await load() } }
        .onChange(of: pose) { _, _ in if mode == .render { Task { await load() } } }
        .onChange(of: renderView) { _, _ in if mode == .render { Task { await load() } } }
        .onChange(of: item) { _, _ in rebuild3D() }
        .onChange(of: armor) { _, _ in rebuild3D(); trimSwatches.removeAll(); Task { await updateSwatches() } }
        .onChange(of: trims) { _, _ in rebuild3D(); Task { await updateSwatches() } }
        .onChange(of: matchAll) { _, _ in rebuild3D(); Task { await updateSwatches() } }
        .onChange(of: allTrim) { _, _ in rebuild3D(); Task { await updateSwatches() } }
        .onChange(of: enchanted) { _, _ in rebuild3D() }
        .onChange(of: biome) { _, _ in Task { await loadBackgrounds() } }
        .onChange(of: blackBg) { _, on in
            if mode == .threeD {
                if on { controller.setBackgroundBlack() }
                else if let bg = background { controller.setBackground(bg) }
            }
        }
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { geo in
            ZStack {
                // Background pinned to the stage size so it can't inflate layout.
                if mode == .render {
                    if blackBg {
                        Color.black
                    } else if let background {
                        Image(nsImage: background).resizable().scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .drawingGroup()   // rasterize once; avoids per-frame fill cost
                    } else {
                        Theme.background
                    }
                }

                if mode == .threeD {
                    if !players.isEmpty { SceneKitView(controller: controller) }
                    else if !loading { placeholder }
                } else if let character {
                    Image(nsImage: character).resizable().scaledToFit()
                        .frame(maxWidth: geo.size.width * 0.95, maxHeight: geo.size.height * characterScale)
                        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                } else if !loading {
                    placeholder
                }

                if loading { ProgressView().controlSize(.large) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.square.badge.camera")
                .font(.system(size: 56, weight: .light)).foregroundStyle(.secondary)
            Text("Enter a Minecraft username").font(.title3.weight(.semibold))
            Text("Render a high-quality character and drop it into a real Minecraft biome — then set it as your wallpaper.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Character", systemImage: "person.crop.square").font(.title3.weight(.semibold))

                GlassEffectContainer {
                    HStack(spacing: 4) {
                        ForEach(Mode.allCases) { m in
                            Button { mode = m } label: {
                                Text(m.rawValue)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(mode == m ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background { if mode == m { Capsule().fill(.white.opacity(0.18)) } }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .glassEffect(.regular, in: .capsule)
                }

                field(mode == .threeD ? "Add players" : "Username") {
                    HStack(spacing: 8) {
                        TextField("e.g. Notch", text: $username)
                            .textFieldStyle(.plain).onSubmit { Task { await load() } }
                        Button { Task { await load() } } label: {
                            if loading { ProgressView().controlSize(.small) }
                            else { Image(systemName: mode == .threeD ? "plus.circle.fill" : "arrow.right.circle.fill") }
                        }
                        .buttonStyle(.plain)
                        .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .glassEffect(.regular, in: .capsule)
                }

                // Added players (3D multiplayer).
                if mode == .threeD && !players.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(players) { p in
                            HStack {
                                Image(systemName: "person.fill").font(.caption2).foregroundStyle(.secondary)
                                Text(p.name).font(.caption)
                                Spacer()
                                Button {
                                    players.removeAll { $0.id == p.id }
                                    controller.scnView.yaws.removeAll()
                                    rebuild3D()
                                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.white.opacity(0.06), in: .capsule)
                        }
                        Text("Drag a character to spin it").font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                if let error { Text(error).font(.caption).foregroundStyle(.orange) }

                if hasContent {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if mode == .render {
                                field("Pose") { menu($pose, SkinRenderService.Pose.allCases) { $0.rawValue } }
                                field("Framing") { menu($renderView, SkinRenderService.RenderView.allCases) { $0.rawValue } }
                                field("Character size") {
                                    Slider(value: $characterScale, in: 0.2...0.95)
                                }
                            } else {
                                Toggle("Hold sword", isOn: Binding(
                                    get: { item == .sword },
                                    set: { item = $0 ? .sword : .none }))
                                    .font(.caption).toggleStyle(.switch).controlSize(.mini)
                                field("Armor") { menu($armor, Armor.allCases) { $0.rawValue } }
                                if armor != .none {
                                    Toggle("Match all pieces", isOn: $matchAll).font(.caption).toggleStyle(.switch).controlSize(.mini)
                                    if matchAll {
                                        trimRow(title: "Armor Trim",
                                                pattern: Binding(get: { allTrim.pattern }, set: { allTrim.pattern = $0 }),
                                                material: Binding(get: { allTrim.material }, set: { allTrim.material = $0 }),
                                                swatch: allTrim)
                                    } else {
                                        ForEach(ArmorPiece.allCases) { piece in
                                            trimRow(title: piece.rawValue,
                                                    pattern: patternBinding(piece),
                                                    material: materialBinding(piece),
                                                    swatch: trims[piece] ?? .init())
                                        }
                                    }
                                    Toggle("Enchanted glint", isOn: $enchanted).font(.caption).toggleStyle(.switch).controlSize(.mini)
                                }
                            }
                            field("Background") { backgroundPicker }
                        }
                    }

                    Button { setWallpaper() } label: {
                        Label("Set as Wallpaper", systemImage: "menubar.dock.rectangle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    if mode == .threeD {
                        Text("Drag to rotate · scroll to zoom").font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let status { Text(status).font(.caption2).foregroundStyle(.secondary) }
                } else { Spacer() }
            }
            .padding(20).frame(maxHeight: .infinity, alignment: .top)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
        .frame(width: 260).padding(.leading, 16).padding(.vertical, 16)
    }

    private var backgroundPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Solid black", isOn: $blackBg).font(.caption).toggleStyle(.switch).controlSize(.mini)
            if !blackBg {
            HStack {
                menu($biome, Biome.allCases) { $0.rawValue }
                if loadingBg { ProgressView().controlSize(.mini) }
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(backgrounds) { bg in
                        Button { Task { await applyBackground(bg) } } label: {
                            Group {
                                if let img = thumbCache[bg.id] {
                                    Image(nsImage: img).resizable()
                                } else {
                                    Rectangle().fill(.quaternary)
                                }
                            }
                            .aspectRatio(16/10, contentMode: .fill)
                            .frame(height: 44).clipShape(.rect(cornerRadius: 6))
                            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.tint, lineWidth: selectedBgID == bg.id ? 2 : 0) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 130)
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func patternBinding(_ p: ArmorPiece) -> Binding<TrimPattern> {
        Binding(get: { trims[p]?.pattern ?? .none }, set: { trims[p, default: .init()].pattern = $0 })
    }
    private func materialBinding(_ p: ArmorPiece) -> Binding<TrimMaterial> {
        Binding(get: { trims[p]?.material ?? .gold }, set: { trims[p, default: .init()].material = $0 })
    }

    private func menu<T: Hashable & Identifiable>(_ selection: Binding<T>, _ all: [T], _ label: @escaping (T) -> String) -> some View {
        Picker("", selection: selection) {
            ForEach(all) { Text(label($0)).tag($0) }
        }.labelsHidden().pickerStyle(.menu)
    }

    private func swatchKey(_ t: PieceTrim) -> String { "\(armor.rawValue)|\(t.pattern.rawValue)|\(t.material.rawValue)" }

    /// A trim picker row: pattern + material menus and a live recolored preview swatch.
    @ViewBuilder
    private func trimRow(title: String, pattern: Binding<TrimPattern>,
                         material: Binding<TrimMaterial>, swatch: PieceTrim) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                menu(pattern, TrimPattern.allCases) { $0.label }
                if swatch.pattern != .none { menu(material, TrimMaterial.allCases) { $0.label } }
            }
            if swatch.pattern != .none, let img = trimSwatches[swatchKey(swatch)] {
                Image(nsImage: img).resizable().interpolation(.none)
                    .aspectRatio(contentMode: .fit).frame(height: 64).frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [.gray.opacity(0.3), .black.opacity(0.4)],
                                               startPoint: .top, endPoint: .bottom))
                    .clipShape(.rect(cornerRadius: 8))
            }
        }
    }

    /// Pre-render swatches showing each active trim composited onto the real armor.
    private func updateSwatches() async {
        guard armor != .none else { return }
        let (a1, _) = await TextureService.shared.armor(armor)
        let tint: NSColor? = armor == .leather ? NSColor(red: 0.65, green: 0.40, blue: 0.25, alpha: 1) : nil
        let active = matchAll ? [allTrim] : ArmorPiece.allCases.map { trims[$0] ?? .init() }
        for t in active where t.pattern != .none && trimSwatches[swatchKey(t)] == nil {
            let (body, _) = await TextureService.shared.trim(t.pattern, t.material)
            if let img = ArmorTrimSwatch.make(armor: a1, trim: body, tint: tint) {
                trimSwatches[swatchKey(t)] = img
            }
        }
    }

    // MARK: Actions

    private func load() async {
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        loading = true; error = nil
        defer { loading = false }
        if mode == .render {
            if let img = await SkinRenderService.render(username: username, pose: pose, view: renderView) {
                character = img; error = nil
            } else if character == nil {
                error = "Couldn't render “\(username)”. Check spelling or try again."
            } else {
                status = "That pose isn't available right now — kept the previous one."
            }
        } else {
            if let skin = try? await SkinService.skin(for: username) {
                skinImage = skin; error = nil
                let name = username.trimmingCharacters(in: .whitespaces)
                if !players.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    players.append(Player(name: name, skin: skin))
                }
                await build3D()
            } else {
                error = "No player found with that username."
            }
        }
        if background == nil { await loadBackgrounds() }
    }

    private func rebuild3D() {
        guard mode == .threeD, !players.isEmpty else { return }
        Task { await build3D() }
    }

    private func pieceTrim(_ p: ArmorPiece) -> PieceTrim { matchAll ? allTrim : (trims[p] ?? .init()) }

    private func build3D() async {
        guard !players.isEmpty else { return }
        let (l1, l2) = await TextureService.shared.armor(armor)
        let sword = item == .sword ? await TextureService.shared.sword(armor) : nil

        // Resolve each piece's trim (body texture for helmet/chest/boots, legs for leggings).
        var helmetT: CGImage?, chestT: CGImage?, leggingsT: CGImage?, bootsT: CGImage?
        if armor != .none {
            let h = pieceTrim(.helmet), c = pieceTrim(.chest), lg = pieceTrim(.leggings), b = pieceTrim(.boots)
            helmetT = (await TextureService.shared.trim(h.pattern, h.material)).0
            chestT = (await TextureService.shared.trim(c.pattern, c.material)).0
            leggingsT = (await TextureService.shared.trim(lg.pattern, lg.material)).1
            bootsT = (await TextureService.shared.trim(b.pattern, b.material)).0
        }

        controller.rebuild(skins: players.map(\.skin), item: item, biome: biome,
                           armorLayer1: l1, armorLayer2: l2, swordTexture: sword,
                           helmetTrim: helmetT, chestTrim: chestT, leggingsTrim: leggingsT, bootsTrim: bootsT,
                           enchanted: enchanted,
                           armorTint: armor == .leather ? NSColor(red: 0.65, green: 0.40, blue: 0.25, alpha: 1) : nil)
        if blackBg { controller.setBackgroundBlack() }
        else if let bg = background { controller.setBackground(bg) }
    }

    private func loadBackgrounds() async {
        loadingBg = true; defer { loadingBg = false }
        guard let result = try? await bgService.search(query: biome.query, sorting: "relevance") else { return }
        backgrounds = result.data
        if let first = result.data.first { await applyBackground(first) }
        await cacheThumbnails(result.data)
    }

    /// Decode small thumbnails once into NSImages so the grid never re-downloads on re-render.
    private func cacheThumbnails(_ photos: [WallhavenPhoto]) async {
        await withTaskGroup(of: (String, NSImage?).self) { group in
            for photo in photos where thumbCache[photo.id] == nil {
                group.addTask {
                    guard let url = URL(string: photo.thumbs.small),
                          let (data, _) = try? await URLSession.shared.data(from: url) else { return (photo.id, nil) }
                    let img = await Task.detached { ImageDownsampler.image(from: data, maxPixel: 320) }.value
                    return (photo.id, img)
                }
            }
            for await (id, img) in group { if let img { thumbCache[id] = img } }
        }
    }

    private func applyBackground(_ photo: WallhavenPhoto) async {
        selectedBgID = photo.id
        // Use the large thumbnail for fast display (full-res only matters when set as wallpaper).
        guard let url = URL(string: photo.thumbs.large),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        // Decode + downsample off the main thread so the UI stays responsive.
        let image = await Task.detached(priority: .userInitiated) {
            ImageDownsampler.image(from: data, maxPixel: 1920)
        }.value
        guard let image else { return }
        background = image
        if mode == .threeD { controller.setBackground(image) }
    }

    private func setWallpaper() {
        let dest = AppPaths.generated.appendingPathComponent("minecraft-\(username).png")
        let out: NSImage
        if mode == .threeD {
            out = controller.snapshot()
        } else {
            guard let character else { return }
            let size = NSScreen.main?.frame.size ?? NSSize(width: 2560, height: 1440)
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let px = NSSize(width: size.width * scale, height: size.height * scale)
            out = NSImage(size: px)
            out.lockFocus()
            if blackBg { NSColor.black.setFill(); NSRect(origin: .zero, size: px).fill() }
            else if let background { drawFill(background, in: NSRect(origin: .zero, size: px)) }
            else { NSColor(Theme.background).setFill(); NSRect(origin: .zero, size: px).fill() }
            let ch = px.height * characterScale
            let cw = ch * (character.size.width / max(character.size.height, 1))
            character.draw(in: NSRect(x: (px.width - cw) / 2, y: (px.height - ch) / 2 * 0.7, width: cw, height: ch))
            out.unlockFocus()
        }
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            status = "Couldn't compose the image."; return
        }
        do {
            try png.write(to: dest)
            library.setWallpaper(dest, allScreens: rotation.allScreens)
            status = "Set \(username) as your wallpaper."
        } catch { status = "Couldn't save: \(error.localizedDescription)" }
    }

    private func drawFill(_ image: NSImage, in rect: NSRect) {
        let imgAspect = image.size.width / max(image.size.height, 1)
        let rectAspect = rect.width / rect.height
        if imgAspect > rectAspect {
            let w = rect.height * imgAspect
            image.draw(in: NSRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: rect.height))
        } else {
            let h = rect.width / imgAspect
            image.draw(in: NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h))
        }
    }
}
