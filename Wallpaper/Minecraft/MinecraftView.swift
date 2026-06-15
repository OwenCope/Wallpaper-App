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

extension TrimMaterial {
    /// Approximate display colour for the material chip.
    var swatchColor: Color {
        switch self {
        case .quartz:    Color(white: 0.93)
        case .iron:      Color(white: 0.75)
        case .gold:      Color(red: 0.95, green: 0.80, blue: 0.25)
        case .lapis:     Color(red: 0.18, green: 0.34, blue: 0.74)
        case .emerald:   Color(red: 0.18, green: 0.78, blue: 0.40)
        case .diamond:   Color(red: 0.40, green: 0.85, blue: 0.85)
        case .netherite: Color(red: 0.28, green: 0.24, blue: 0.26)
        case .redstone:  Color(red: 0.82, green: 0.16, blue: 0.12)
        case .copper:    Color(red: 0.78, green: 0.46, blue: 0.30)
        case .amethyst:  Color(red: 0.62, green: 0.42, blue: 0.86)
        case .resin:     Color(red: 0.95, green: 0.55, blue: 0.15)
        }
    }
}

extension View {
    /// Shrinks and fades a row as it scrolls out the top of its ScrollView.
    func fadesOnScroll() -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(phase == .topLeading ? 0 : 1)
                .scaleEffect(phase == .topLeading ? 0.85 : 1, anchor: .top)
        }
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
    private var lastSkinCount = -1
    func rebuild(skins: [NSImage], equips: [PlayerEquip], biome: Biome) {
        // 1 player → free camera orbit (old feel); multiple → per-character drag.
        let single = skins.count <= 1
        scnView.allowsCameraControl = single
        // Capture the live camera so an armor/trim tweak doesn't snap the view back.
        let prevTransform = scnView.pointOfView?.transform
        let sameCount = skins.count == lastSkinCount
        lastSkinCount = skins.count
        let rotations = (0..<skins.count).map { scnView.yaws[$0] ?? 0 }
        scnView.scene = MinecraftModel.scene(skins: skins, equips: equips, biome: biome, rotations: rotations)
        let cam = scnView.scene?.rootNode.childNode(withName: "camera", recursively: false)
        if single {
            // Keep the user's orbit/zoom across rebuilds (only reframe when the cast changes).
            if sameCount, let prevTransform { cam?.transform = prevTransform }
            scnView.pointOfView = cam
        } else {
            scnView.pointOfView = cam
            scnView.baseCameraZ = cam?.position.z ?? 62
            scnView.applyZoom()
        }
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
    /// Short label for the segmented piece selector.
    var short: String {
        switch self { case .helmet: "Helm"; case .chest: "Chest"; case .leggings: "Legs"; case .boots: "Boots" }
    }
    /// Suffix for the armor item texture (e.g. "chestplate").
    var itemFile: String {
        switch self { case .helmet: "helmet"; case .chest: "chestplate"; case .leggings: "leggings"; case .boots: "boots" }
    }
}

struct PieceTrim: Equatable {
    var pattern: TrimPattern = .none
    var material: TrimMaterial = .gold
}

/// One character's full armor/weapon configuration. Stored per-player so each
/// character in a multiplayer scene can wear different armor and trims.
struct Loadout: Equatable {
    var item: HeldItem = .none
    var armor: Armor = .none
    var matchAll = true
    var allTrim = PieceTrim()
    var trims: [ArmorPiece: PieceTrim] = [
        .helmet: .init(), .chest: .init(), .leggings: .init(), .boots: .init()]
    var enchanted = false
}

struct Player: Identifiable {
    let id = UUID()
    let name: String
    let skin: NSImage
    var yaw: Double = 0   // degrees, individual rotation
    var loadout = Loadout()
}

/// Leather armor is greyscale and gets dyed by multiplying with this colour.
let mcLeatherTint = NSColor(red: 0.65, green: 0.40, blue: 0.25, alpha: 1)

func loadoutBinding(_ store: MinecraftStore, _ i: Int) -> Binding<Loadout> {
    Binding(get: { store.players[i].loadout }, set: { store.players[i].loadout = $0 })
}
func piecePatternBinding(_ lo: Binding<Loadout>, _ p: ArmorPiece) -> Binding<TrimPattern> {
    Binding(get: { lo.wrappedValue.trims[p]?.pattern ?? .none },
            set: { lo.wrappedValue.trims[p, default: .init()].pattern = $0 })
}
func pieceMaterialBinding(_ lo: Binding<Loadout>, _ p: ArmorPiece) -> Binding<TrimMaterial> {
    Binding(get: { lo.wrappedValue.trims[p]?.material ?? .gold },
            set: { lo.wrappedValue.trims[p, default: .init()].material = $0 })
}

/// Shared Minecraft editor state — owned at app level so the main 3D view and
/// the pop-out Trim Studio window edit the *same* characters and see live updates.
@MainActor
final class MinecraftStore: ObservableObject {
    @Published var players: [Player] = []
    @Published var selectedPlayerID: UUID?
    /// Official Minecraft item icons, cached by key (templates, materials, armor pieces).
    @Published var icons: [String: NSImage] = [:]
    /// Live front-facing composite of the selected character + armor + trims (Studio backdrop).
    @Published var preview: NSImage?
    /// Monotonic build counter so out-of-order async rebuilds can no-op (prevents flicker/revert).
    var buildGen = 0

    var selectedIndex: Int? {
        if let id = selectedPlayerID, let i = players.firstIndex(where: { $0.id == id }) { return i }
        return players.isEmpty ? nil : 0
    }
    var currentLoadout: Loadout? {
        guard let i = selectedIndex, players.indices.contains(i) else { return nil }
        return players[i].loadout
    }
    /// String fingerprint of every player's loadout — drives scene rebuilds on any change.
    var loadoutSignature: String {
        players.map { p in
            let l = p.loadout
            let perPiece = ArmorPiece.allCases.map { "\($0.rawValue)=\(l.trims[$0]?.pattern.rawValue ?? "-")/\(l.trims[$0]?.material.rawValue ?? "-")" }.joined(separator: ",")
            return "\(p.id)|\(l.armor.rawValue)|\(l.item.rawValue)|\(l.matchAll)|\(l.allTrim.pattern.rawValue)/\(l.allTrim.material.rawValue)|\(perPiece)|\(l.enchanted)"
        }.joined(separator: ";")
    }

    // MARK: Official item icons

    nonisolated static func templateKey(_ p: TrimPattern) -> String { "tpl:\(p.rawValue)" }
    nonisolated static func materialKey(_ m: TrimMaterial) -> String { "mat:\(m.rawValue)" }
    nonisolated static func armorKey(_ a: Armor, _ piece: ArmorPiece) -> String { "arm:\(a.rawValue):\(piece.rawValue)" }

    private func cache(_ key: String, _ cg: CGImage?) {
        guard let cg, icons[key] == nil else { return }
        icons[key] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Load every template + material icon (and the armor's piece icons) for the picker, concurrently.
    func loadIcons(for armor: Armor) async {
        await withTaskGroup(of: (String, CGImage?).self) { group in
            for p in TrimPattern.allCases where p != .none && icons[Self.templateKey(p)] == nil {
                group.addTask { (Self.templateKey(p), await TextureService.shared.trimTemplate(p)) }
            }
            for m in TrimMaterial.allCases where icons[Self.materialKey(m)] == nil {
                group.addTask { (Self.materialKey(m), await TextureService.shared.materialItem(m)) }
            }
            if armor != .none {
                for piece in ArmorPiece.allCases where icons[Self.armorKey(armor, piece)] == nil {
                    group.addTask { (Self.armorKey(armor, piece), await TextureService.shared.armorItem(armor, piece.itemFile)) }
                }
            }
            for await (key, cg) in group { cache(key, cg) }
        }
    }

    /// Recompose the front-facing preview of the selected player's current loadout.
    func updatePreview() async {
        guard let i = selectedIndex, players.indices.contains(i),
              let skinCG = players[i].skin.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            preview = nil; return
        }
        let lo = players[i].loadout
        let (a1, a2) = await TextureService.shared.armor(lo.armor)
        let tint: NSColor? = lo.armor == .leather ? mcLeatherTint : nil
        func pt(_ p: ArmorPiece) -> PieceTrim { lo.matchAll ? lo.allTrim : (lo.trims[p] ?? .init()) }
        let h = pt(.helmet), c = pt(.chest), lg = pt(.leggings), b = pt(.boots)
        let helmetT = (await TextureService.shared.trim(h.pattern, h.material)).0
        let chestT = (await TextureService.shared.trim(c.pattern, c.material)).0
        let legT = (await TextureService.shared.trim(lg.pattern, lg.material)).1
        let bootT = (await TextureService.shared.trim(b.pattern, b.material)).0
        preview = ArmorPreview.paperDoll(skin: skinCG, layer1: a1, layer2: a2,
                                         helmetTrim: helmetT, chestTrim: chestT,
                                         leggingsTrim: legT, bootsTrim: bootT, tint: tint)
    }
}

struct MinecraftView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case render = "2D Render", threeD = "3D Rotate"
        var id: String { rawValue }
    }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rotation: RotationManager
    @AppStorage("wallhaven.apiKey") private var apiKey = ""
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: MinecraftStore
    @StateObject private var controller = SceneController()

    @State private var mode: Mode = .render
    @State private var username = ""
    @State private var pose: SkinRenderService.Pose = .default
    @State private var renderView: SkinRenderService.RenderView = .full
    @State private var biome: Biome = .plains

    // Shared editor state lives in `store`; these proxies keep call sites tidy.
    private var players: [Player] {
        get { store.players } nonmutating set { store.players = newValue }
    }
    private var selectedPlayerID: UUID? {
        get { store.selectedPlayerID } nonmutating set { store.selectedPlayerID = newValue }
    }
    private var selectedIndex: Int? { store.selectedIndex }

    @State private var character: NSImage?    // 2D render
    @State private var skinImage: NSImage?     // raw skin for 3D (most recent)
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

    private var loadoutSignature: String { store.loadoutSignature }

    var body: some View {
        ZStack(alignment: .leading) {
            // Stage fills the whole window (under the toolbar too) and runs
            // behind the floating sidebar.
            stage.frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            sidebar.padding(.top, 54)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .onChange(of: mode) { _, _ in Task { await load() } }
        .onChange(of: pose) { _, _ in if mode == .render { Task { await load() } } }
        .onChange(of: renderView) { _, _ in if mode == .render { Task { await load() } } }
        // Any change to any player's loadout rebuilds the scene.
        .onChange(of: loadoutSignature) { _, _ in rebuild3D() }
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
                // Drawn in both modes so the stage color matches; in 3D the
                // SceneKit view covers it once players are added.
                if blackBg {
                    Color.black
                } else if mode == .render, let background {
                    Image(nsImage: background).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .drawingGroup()   // rasterize once; avoids per-frame fill cost
                } else {
                    Color.black
                }

                // The stage spans the whole window; the sidebar floats over its
                // left edge, so center content within the *visible* region by
                // insetting it by the sidebar's footprint.
                let sidebarInset: CGFloat = 292
                if mode == .threeD {
                    if !players.isEmpty { SceneKitView(controller: controller) }
                    else if !loading { placeholder.padding(.leading, sidebarInset) }
                } else if let character {
                    Image(nsImage: character).resizable().scaledToFit()
                        .frame(maxWidth: (geo.size.width - sidebarInset) * 0.95,
                               maxHeight: geo.size.height * characterScale)
                        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                        .padding(.leading, sidebarInset)
                } else if !loading {
                    placeholder.padding(.leading, sidebarInset)
                }

                if loading { ProgressView().controlSize(.large).padding(.leading, sidebarInset) }
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
                HStack {
                    Label("Character", systemImage: "person.crop.square").font(.title3.weight(.semibold))
                    Spacer()
                    Button { openWindow(id: "minecraft") } label: {
                        Image(systemName: "macwindow.on.rectangle").font(.callout)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Open the editor in its own window")
                }

                // Everything below the title scrolls; the header controls
                // shrink and fade out as they slide under the title.
                scrollableIfNeeded {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassSegmentBar(items: Mode.allCases, label: \.rawValue,
                                        selection: $mode, itemWidth: 106)
                            .fadesOnScroll()

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
                        .fadesOnScroll()

                        // Added players (3D multiplayer). Tap one to edit its armor.
                        if mode == .threeD && !players.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(players) { p in
                                    let isSel = selectedIndex.map { players[$0].id == p.id } ?? false
                                    HStack {
                                        Image(systemName: isSel ? "person.fill.checkmark" : "person.fill")
                                            .font(.caption2).foregroundStyle(isSel ? Color.accentColor : .secondary)
                                        Text(p.name).font(.caption).fontWeight(isSel ? .semibold : .regular)
                                        Spacer()
                                        Button {
                                            players.removeAll { $0.id == p.id }
                                            controller.scnView.yaws.removeAll()
                                            if selectedPlayerID == p.id { selectedPlayerID = players.first?.id }
                                            rebuild3D()
                                        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(isSel ? Color.accentColor.opacity(0.18) : .white.opacity(0.06), in: .capsule)
                                    .contentShape(.capsule)
                                    .onTapGesture { selectedPlayerID = p.id }
                                }
                                Text(players.count > 1 ? "Tap to edit a character · drag to spin it"
                                                       : "Drag a character to spin it")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            .fadesOnScroll()
                        }

                        if let error { Text(error).font(.caption).foregroundStyle(.orange).fadesOnScroll() }

                        if hasContent {
                            if mode == .render {
                                settingRow("Pose", icon: "figure.walk", tint: .teal) {
                                    menu($pose, SkinRenderService.Pose.allCases) { $0.rawValue }
                                }
                                settingRow("Framing", icon: "crop", tint: .indigo) {
                                    menu($renderView, SkinRenderService.RenderView.allCases) { $0.rawValue }
                                }
                                sliderRow("Character size", icon: "arrow.up.left.and.arrow.down.right", tint: .orange,
                                          value: $characterScale, range: 0.2...0.95)
                            } else if let i = selectedIndex, players.indices.contains(i) {
                                armorControls(loadoutBinding(store, i), multiplayer: players.count > 1,
                                              name: players[i].name)
                            }
                            field("Background") { backgroundPicker }
                        }
                    }
                }

                if hasContent {
                    Button { setWallpaper() } label: {
                        Label("Set as Wallpaper", systemImage: "checkmark")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    if mode == .threeD {
                        Text("Drag to rotate · scroll to zoom").font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let status { Text(status).font(.caption2).foregroundStyle(.secondary) }
                }
            }
            // Hug the content when idle; only fill the window once the
            // option controls are showing.
            .padding(20).frame(maxHeight: hasContent ? .infinity : nil, alignment: .top)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
        .frame(width: 260).padding(.leading, 16).padding(.vertical, 16)
    }

    private var backgroundPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingRow("Solid black", icon: "circle.lefthalf.filled", tint: .gray) {
                Toggle("", isOn: $blackBg)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            if !blackBg {
            settingRow("Biome", icon: "leaf.fill", tint: .green) {
                HStack(spacing: 6) {
                    if loadingBg { ProgressView().controlSize(.mini) }
                    menu($biome, Biome.allCases) { $0.rawValue }
                }
            }
            ScrollView(showsIndicators: false) {
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

    /// Scrolls only once option controls exist; otherwise the panel hugs its content.
    @ViewBuilder
    private func scrollableIfNeeded<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if hasContent {
            ScrollView(showsIndicators: false) { content() }
        } else {
            content()
        }
    }

    /// Settings-style row: colored icon chip + label, control on the trailing edge.
    private func settingRow<Content: View>(_ title: String, icon: String, tint: Color,
                                           @ViewBuilder trailing: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint.gradient, in: .rect(cornerRadius: 6))
            Text(title).font(.callout)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
    }

    /// Same look as settingRow, with the slider on its own line underneath.
    private func sliderRow(_ title: String, icon: String, tint: Color,
                           value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(tint.gradient, in: .rect(cornerRadius: 6))
                Text(title).font(.callout)
            }
            Slider(value: value, in: range)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
    }

    // MARK: Armor controls (per selected player)

    /// The full armor/trim editor, bound to one player's loadout.
    @ViewBuilder
    private func armorControls(_ lo: Binding<Loadout>, multiplayer: Bool, name: String) -> some View {
        let l = lo.wrappedValue
        if multiplayer {
            Text("Editing \(name)").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        settingRow("Held item", icon: "figure.fencing", tint: .orange) {
            menu(lo.item, HeldItem.allCases) { $0.rawValue }
        }
        settingRow("Armor", icon: "shield.fill", tint: .blue) { menu(lo.armor, Armor.allCases) { $0.rawValue } }
        if l.armor != .none {
            settingRow("Match all pieces", icon: "link", tint: .purple) {
                Toggle("", isOn: lo.matchAll).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            if l.matchAll {
                TrimRow(armor: l.armor, title: "All pieces", piece: nil,
                        pattern: lo.allTrim.pattern, material: lo.allTrim.material)
            } else {
                ForEach(ArmorPiece.allCases) { piece in
                    TrimRow(armor: l.armor, title: piece.rawValue, piece: piece,
                            pattern: piecePatternBinding(lo, piece), material: pieceMaterialBinding(lo, piece))
                }
            }
            settingRow("Enchanted glint", icon: "sparkles", tint: .pink) {
                Toggle("", isOn: lo.enchanted).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
    }

    private func menu<T: Hashable & Identifiable>(_ selection: Binding<T>, _ all: [T], _ label: @escaping (T) -> String) -> some View {
        Picker("", selection: selection) {
            ForEach(all) { Text(label($0)).tag($0) }
        }.labelsHidden().pickerStyle(.menu)
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
                if let existing = players.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    selectedPlayerID = existing.id   // re-select if already added
                } else {
                    let player = Player(name: name, skin: skin)
                    players.append(player)
                    selectedPlayerID = player.id     // edit the newcomer
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
        store.buildGen += 1
        let gen = store.buildGen
        Task { await build3D(gen) }
    }

    private func pieceTrim(_ lo: Loadout, _ p: ArmorPiece) -> PieceTrim {
        lo.matchAll ? lo.allTrim : (lo.trims[p] ?? .init())
    }

    /// Resolve every player's loadout into rendered textures, in player order.
    /// `gen` (when set) is the rebuild request id; a stale request no-ops at the end.
    private func build3D(_ gen: Int? = nil) async {
        guard !players.isEmpty else { return }
        var equips: [PlayerEquip] = []
        for p in players {
            let lo = p.loadout
            let (l1, l2) = await TextureService.shared.armor(lo.armor)
            let sword = await TextureService.shared.held(lo.item, lo.armor)
            var helmetT: CGImage?, chestT: CGImage?, leggingsT: CGImage?, bootsT: CGImage?
            if lo.armor != .none {
                let h = pieceTrim(lo, .helmet), c = pieceTrim(lo, .chest)
                let lg = pieceTrim(lo, .leggings), b = pieceTrim(lo, .boots)
                helmetT = (await TextureService.shared.trim(h.pattern, h.material)).0
                chestT = (await TextureService.shared.trim(c.pattern, c.material)).0
                leggingsT = (await TextureService.shared.trim(lg.pattern, lg.material)).1
                bootsT = (await TextureService.shared.trim(b.pattern, b.material)).0
            }
            equips.append(PlayerEquip(armorLayer1: l1, armorLayer2: l2, swordTexture: sword,
                                      helmetTrim: helmetT, chestTrim: chestT,
                                      leggingsTrim: leggingsT, bootsTrim: bootsT,
                                      enchanted: lo.enchanted,
                                      armorTint: lo.armor == .leather ? mcLeatherTint : nil,
                                      item: lo.item))
        }
        // A newer rebuild was requested while we were fetching — drop this stale result.
        if let gen, gen != store.buildGen { return }
        controller.rebuild(skins: players.map(\.skin), equips: equips, biome: biome)
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

// MARK: - Reusable trim "recipe" row

/// One armor piece's trim, laid out like Minecraft's smithing recipe:
/// **Pattern · Armor piece · Material**, using the official item textures.
/// Adapts to any width, so it's shared by the narrow sidebar and the roomy Studio.
struct TrimRow: View {
    @EnvironmentObject private var store: MinecraftStore
    let armor: Armor
    let title: String          // "Helmet" / "All pieces"
    let piece: ArmorPiece?     // nil = "All pieces" → show chestplate as the representative icon
    @Binding var pattern: TrimPattern
    @Binding var material: TrimMaterial

    @State private var showPatterns = false
    @State private var showMaterials = false

    private var armorPiece: ArmorPiece { piece ?? .chest }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                // Pattern (smithing template)
                cell(caption: pattern == .none ? "Add trim" : pattern.label, action: { showPatterns = true }) {
                    if pattern == .none {
                        Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                    } else {
                        icon(store.icons[MinecraftStore.templateKey(pattern)])
                    }
                }
                .popover(isPresented: $showPatterns, arrowEdge: .bottom) { patternPicker }

                plus
                // Armor piece (the gear being trimmed)
                cell(caption: armor.rawValue) { icon(store.icons[MinecraftStore.armorKey(armor, armorPiece)]) }
                plus
                // Material
                cell(caption: pattern == .none ? "—" : material.label,
                     dimmed: pattern == .none,
                     action: pattern == .none ? nil : { showMaterials = true }) {
                    icon(store.icons[MinecraftStore.materialKey(material)]).opacity(pattern == .none ? 0.3 : 1)
                }
                .popover(isPresented: $showMaterials, arrowEdge: .bottom) { materialPicker }
            }
        }
        .task { await store.loadIcons(for: armor) }
    }

    private var plus: some View { Image(systemName: "plus").font(.caption2).foregroundStyle(.tertiary) }

    @ViewBuilder private func icon(_ img: NSImage?) -> some View {
        if let img {
            Image(nsImage: img).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
        } else {
            ProgressView().controlSize(.mini)
        }
    }

    @ViewBuilder
    private func cell<Top: View>(caption: String, dimmed: Bool = false, action: (() -> Void)? = nil,
                                 @ViewBuilder top: () -> Top) -> some View {
        let body = VStack(spacing: 4) {
            ZStack { top() }.frame(height: 30)
            Text(caption).font(.system(size: 9)).lineLimit(1).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8).padding(.horizontal, 4)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 10))
        .overlay {
            if action != nil {
                RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
        }
        if let action {
            Button(action: action) { body }.buttonStyle(.plain)
        } else {
            body.opacity(dimmed ? 0.6 : 1)
        }
    }

    private var patternPicker: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                patternTile(.none)
                ForEach(TrimPattern.allCases.filter { $0 != .none }) { patternTile($0) }
            }
            .padding(14)
        }
        .frame(width: 300, height: 360)
    }

    @ViewBuilder private func patternTile(_ p: TrimPattern) -> some View {
        let selected = pattern == p
        Button { pattern = p; showPatterns = false } label: {
            VStack(spacing: 4) {
                ZStack {
                    if p == .none { Image(systemName: "nosign").font(.system(size: 18)).foregroundStyle(.secondary) }
                    else { icon(store.icons[MinecraftStore.templateKey(p)]) }
                }
                .frame(height: 40).frame(maxWidth: .infinity)
                Text(p == .none ? "None" : p.label).font(.system(size: 9)).lineLimit(1)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .padding(5)
            .background(selected ? Color.accentColor.opacity(0.3) : .white.opacity(0.05), in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.tint, lineWidth: selected ? 2 : 0) }
        }
        .buttonStyle(.plain)
    }

    private var materialPicker: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(TrimMaterial.allCases) { m in
                    Button { material = m; showMaterials = false } label: {
                        VStack(spacing: 4) {
                            icon(store.icons[MinecraftStore.materialKey(m)]).frame(height: 28)
                            Text(m.label).font(.system(size: 9)).lineLimit(1)
                                .foregroundStyle(material == m ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity).padding(6)
                        .background(material == m ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        .frame(width: 260, height: 260)
    }
}

// MARK: - Trim Studio (pop-out window)

/// Standalone window that edits the selected character's armor trims — every
/// piece shown at once. Shares `MinecraftStore`, so the main 3D view updates live.
struct MinecraftTrimsView: View {
    @EnvironmentObject private var store: MinecraftStore

    var body: some View {
        ZStack(alignment: .trailing) {
            Color(white: 0.10).ignoresSafeArea()
            // Live preview of the selected character, parked on the back-right.
            if let img = store.preview {
                Image(nsImage: img).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                    .padding(.vertical, 48).padding(.trailing, 44)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .shadow(color: .black.opacity(0.55), radius: 22, y: 6)
                    .allowsHitTesting(false)
            }
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Armor Trims", systemImage: "tshirt").font(.title2.weight(.semibold))

                if store.players.isEmpty {
                    ContentUnavailableView("No character yet", systemImage: "person.crop.square",
                        description: Text("Add a character in the main window, then design its armor trims here."))
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else if let i = store.selectedIndex, store.players.indices.contains(i) {
                    let lo = loadoutBinding(store, i)
                    if store.players.count > 1 {
                        Picker("Character", selection: Binding(
                            get: { store.selectedPlayerID ?? store.players[i].id },
                            set: { store.selectedPlayerID = $0 })) {
                            ForEach(store.players) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.segmented)
                    }
                    HStack(spacing: 12) {
                        Text("Armor").foregroundStyle(.secondary)
                        Picker("", selection: lo.armor) {
                            ForEach(Armor.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().fixedSize()
                        Spacer()
                        Picker("", selection: lo.item) {
                            ForEach(HeldItem.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().fixedSize()
                        Toggle("Glint", isOn: lo.enchanted)
                    }
                    if lo.wrappedValue.armor == .none {
                        Text("Pick an armor type above to start adding trims.")
                            .foregroundStyle(.secondary).padding(.top, 8)
                    } else {
                        HStack {
                            Text("Trims").font(.headline)
                            Spacer()
                            Toggle("Same on every piece", isOn: lo.matchAll)
                                .toggleStyle(.switch).controlSize(.small)
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            if lo.wrappedValue.matchAll {
                                TrimRow(armor: lo.wrappedValue.armor, title: "All pieces", piece: nil,
                                        pattern: lo.allTrim.pattern, material: lo.allTrim.material)
                            } else {
                                ForEach(ArmorPiece.allCases) { piece in
                                    TrimRow(armor: lo.wrappedValue.armor, title: piece.rawValue, piece: piece,
                                            pattern: piecePatternBinding(lo, piece),
                                            material: pieceMaterialBinding(lo, piece))
                                }
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.05), in: .rect(cornerRadius: 16))
                        Text("Tap a tile to choose a pattern, then its material — just like a smithing table.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(28).frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: store.loadoutSignature) {
            if let a = store.currentLoadout?.armor { await store.loadIcons(for: a) }
            await store.updatePreview()
        }
    }
}
