import SwiftUI
import ImageIO

/// A wallpaper to preview full-screen before applying. Built by each source
/// (local file or remote photo) so the detail view stays source-agnostic.
struct PreviewItem: Identifiable {
    let id = UUID()
    let title: String
    /// Optional async upgrade to a nicer title (e.g. fetched Wallhaven tags).
    var titleProvider: (() async -> String?)? = nil
    let resolution: String?
    let fileSizeBytes: Int?
    let shareURL: URL?
    var isFavorite: Bool = false
    var onToggleFavorite: (() -> Void)? = nil
    let image: AnyView
    /// Apply the wallpaper. `screen == nil` means all displays.
    let apply: (_ screen: NSScreen?) async -> Void
}

/// Holds the currently-previewed wallpaper; the window overlays the detail view
/// whenever `item` is non-nil.
@MainActor
final class PreviewCoordinator: ObservableObject {
    @Published var item: PreviewItem?
    func present(_ item: PreviewItem) { self.item = item }
    func dismiss() { item = nil }
}

struct WallpaperDetailView: View {
    let item: PreviewItem
    @EnvironmentObject private var coordinator: PreviewCoordinator
    @State private var favorite: Bool
    @State private var showApplyPopover = false
    @State private var applying = false
    @State private var displayTitle: String

    init(item: PreviewItem) {
        self.item = item
        _favorite = State(initialValue: item.isFavorite)
        _displayTitle = State(initialValue: item.title)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            item.image
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()

            // Top-right close.
            VStack {
                HStack {
                    Spacer()
                    Button { coordinator.dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                Spacer()
            }
            .padding(20)

            // Bottom floating control bar.
            VStack {
                Spacer()
                bottomBar
            }
            .padding(.bottom, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 1.02)))
        .task {
            if let provider = item.titleProvider, let nicer = await provider() {
                withAnimation(.easeOut(duration: 0.2)) { displayTitle = nicer }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            Button { coordinator.dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle).font(.headline).lineLimit(1)
                HStack(spacing: 12) {
                    if let resolution = item.resolution {
                        Label(resolution, systemImage: "aspectratio").labelStyle(.titleAndIcon)
                    }
                    if let size = item.fileSizeBytes, size > 0 {
                        Label(formatBytes(size), systemImage: "doc").labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 160, alignment: .leading)

            Spacer()

            if let shareURL = item.shareURL {
                ShareLink(item: shareURL) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.plain)
            }

            if item.onToggleFavorite != nil {
                Button {
                    favorite.toggle()
                    item.onToggleFavorite?()
                } label: {
                    Image(systemName: favorite ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(favorite ? .pink : .primary)
                }
                .buttonStyle(.plain)
            }

            Button { showApplyPopover = true } label: {
                Group {
                    if applying { ProgressView().controlSize(.small) }
                    else { Label("Set Wallpaper", systemImage: "checkmark").font(.callout.weight(.semibold)) }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .popover(isPresented: $showApplyPopover, arrowEdge: .top) {
                // Popovers are separate windows — they don't inherit the main
                // window's dark scheme, so re-assert it here.
                applyPopover
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 640)
    }

    private var applyPopover: some View {
        ApplyOptionsView(applying: $applying) { screen in
            showApplyPopover = false
            applying = true
            Task {
                await item.apply(screen)
                applying = false
                coordinator.dismiss()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}

/// The "Both / Desktop / Lockscreen" + display picker popover.
private struct ApplyOptionsView: View {
    @Binding var applying: Bool
    let onApply: (_ screen: NSScreen?) -> Void

    enum Scope: String, CaseIterable { case both = "Both", desktop = "Desktop", lockscreen = "Lockscreen" }
    @State private var scope: Scope = .desktop
    @State private var allDisplays = true
    @State private var selected: Int = 0   // index into NSScreen.screens

    private var screens: [NSScreen] { NSScreen.screens }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSegmentBar(items: Scope.allCases, label: \.rawValue,
                            selection: $scope, itemWidth: 80)

            if scope != .desktop {
                Text("macOS only allows apps to change the desktop, so this will set the desktop wallpaper.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Text("Choose display").font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.2)) { allDisplays.toggle() }
                } label: {
                    Text("All")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(allDisplays ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background { if allDisplays { Capsule().fill(.white.opacity(0.18)) } }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            if !allDisplays {
                ForEach(Array(screens.enumerated()), id: \.offset) { idx, screen in
                    Button { selected = idx } label: {
                        HStack {
                            Image(systemName: "display")
                            VStack(alignment: .leading) {
                                Text(screen.localizedName).font(.callout.weight(.medium))
                                Text(idx == 0 ? "Main" : "Display \(idx + 1)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selected == idx { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(selected == idx ? 0.12 : 0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                let screen: NSScreen? = allDisplays ? nil : screens[safe: selected]
                onApply(screen)
            } label: {
                Label("Set Wallpaper", systemImage: "checkmark")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(16)
        .frame(width: 280)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Builders

extension PreviewItem {
    /// Build a preview for a local image file.
    @MainActor
    static func local(_ url: URL, library: LibraryStore) -> PreviewItem {
        PreviewItem(
            title: url.deletingPathExtension().lastPathComponent,
            resolution: pixelSize(of: url),
            fileSizeBytes: fileSize(of: url),
            shareURL: url,
            isFavorite: library.isFavorite(url),
            onToggleFavorite: { library.toggleFavorite(url) },
            image: AnyView(
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable() } else { Color.black }
                }
            ),
            apply: { screen in
                if let screen { WallpaperManager.set(url, on: screen) }
                else { WallpaperManager.setOnAllScreens(url) }
                library.currentWallpaper = url
            }
        )
    }

    /// Build a preview for a remote Wallhaven photo (downloads on apply).
    @MainActor
    static func remote(_ photo: WallhavenPhoto, service: WallhavenService, library: LibraryStore) -> PreviewItem {
        PreviewItem(
            title: "Wallhaven #\(photo.id)",
            titleProvider: { await service.title(for: photo) },
            resolution: photo.resolution,
            fileSizeBytes: photo.file_size,
            shareURL: URL(string: photo.url),
            image: AnyView(
                // Show the small thumb instantly, then the full-res image when ready.
                ZStack {
                    AsyncImage(url: URL(string: photo.thumbs.large)) { img in img.resizable() } placeholder: { Color.black }
                    AsyncImage(url: URL(string: photo.path)) { phase in
                        if let img = phase.image { img.resizable() } else { Color.clear }
                    }
                }
            ),
            apply: { screen in
                guard let local = try? await service.download(photo) else { return }
                if let screen { WallpaperManager.set(local, on: screen) }
                else { WallpaperManager.setOnAllScreens(local) }
                library.currentWallpaper = local
            }
        )
    }

    private static func pixelSize(of url: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return "\(w)×\(h)"
    }

    private static func fileSize(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int
    }
}
