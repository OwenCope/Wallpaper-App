import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case explore = "Explore"
    case library = "Library"
    case minecraft = "Minecraft"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var collections: CollectionStore
    @EnvironmentObject private var preview: PreviewCoordinator
    @State private var tab: AppTab = .home
    @State private var exploreQuery = ""
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            // Keep all tabs alive and toggle visibility — recreating them on
            // every switch reloads their content and makes the UI flash.
            ZStack {
                HomeView(tab: $tab, exploreQuery: $exploreQuery)
                    .opacity(tab == .home ? 1 : 0).allowsHitTesting(tab == .home)
                ExploreView(query: $exploreQuery)
                    .opacity(tab == .explore ? 1 : 0).allowsHitTesting(tab == .explore)
                LibraryHubView()
                    .opacity(tab == .library ? 1 : 0).allowsHitTesting(tab == .library)
                MinecraftView()
                    .opacity(tab == .minecraft ? 1 : 0).allowsHitTesting(tab == .minecraft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            topBar

            // Full-screen wallpaper preview overlay.
            if let item = preview.item {
                WallpaperDetailView(item: item)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.2), value: preview.item?.id)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .background(WindowDragConfigurator())
    }

    // MARK: - Floating top bar (iPadOS-style glass tab bar)

    private var topBar: some View {
        HStack(spacing: 12) {
            wordmark

            Spacer()

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    GlassSegmentBar(items: AppTab.allCases, label: \.rawValue,
                                    selection: $tab, commandShortcuts: true)
                    circleButton("magnifyingglass", help: "Search wallpapers") { tab = .explore }
                }
            }

            Spacer()

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    circleButton("plus", help: "Add to library") { tab = .library }
                    circleButton("gearshape", help: "Settings (⌘,)") { showSettings = true }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .background {
            // Standard macOS Settings shortcut for the in-window settings sheet.
            Button("") { showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        }
    }

    private var wordmark: some View {
        HStack(spacing: 10) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 13, weight: .semibold))
                // Dark mode: white logo on black. Light mode: black logo on white.
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .frame(width: 28, height: 28)
                .background(colorScheme == .dark ? .black : .white, in: .rect(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.12)))
            Text("Wallpaper").font(.headline.weight(.semibold))
        }
        .fixedSize()
    }

    private func circleButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(help)
    }
}

/// iPadOS-26-style glass segment bar: the selection capsule can be dragged
/// along the bar and follows the pointer with a spring, snapping to the
/// nearest item on release. Clicking an item still works, with the capsule
/// sliding over. Reused for the main tabs, Library pages, and pickers.
struct GlassSegmentBar<T: Hashable>: View {
    let items: [T]
    let label: (T) -> String
    @Binding var selection: T
    var itemWidth: CGFloat = 100
    var commandShortcuts = false   // ⌘1…⌘n

    /// Continuous highlight position (in item units) while dragging; nil when idle.
    @State private var dragPosition: Double?
    @State private var pressed = false

    private let itemHeight: CGFloat = 32
    private var selectedIndex: Int { items.firstIndex(of: selection) ?? 0 }

    var body: some View {
        ZStack(alignment: .leading) {
            // Selection highlight — follows the pointer while dragging.
            Capsule()
                .fill(.white.opacity(pressed ? 0.26 : 0.18))
                .frame(width: itemWidth, height: itemHeight)
                .scaleEffect(pressed ? 1.06 : 1.0)
                .offset(x: highlightOffset)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.72), value: highlightOffset)
                .animation(.snappy(duration: 0.2), value: pressed)

            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    button(for: item, at: index)
                }
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .highPriorityGesture(dragGesture)
    }

    @ViewBuilder
    private func button(for item: T, at index: Int) -> some View {
        let base = Button {
            selection = item
        } label: {
            Text(label(item))
                .font(.callout.weight(.medium))
                .foregroundStyle(selection == item ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: itemWidth, height: itemHeight)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)

        if commandShortcuts, index < 9 {
            base
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .help("\(label(item)) (⌘\(index + 1))")
        } else {
            base.help(label(item))
        }
    }

    private var highlightOffset: CGFloat {
        CGFloat(dragPosition ?? Double(selectedIndex)) * itemWidth
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                pressed = true
                // Center the capsule under the pointer, clamped to the bar.
                let raw = (value.location.x - 4) / itemWidth - 0.5
                dragPosition = min(max(raw, 0), Double(items.count - 1))
            }
            .onEnded { value in
                pressed = false
                let raw = (value.location.x - 4) / itemWidth - 0.5
                let snapped = Int((min(max(raw, 0), Double(items.count - 1))).rounded())
                selection = items[snapped]
                dragPosition = nil
            }
    }
}

/// Lets the window be moved by dragging anywhere on its background
/// (toolbar included), like Finder/Music side areas.
private struct WindowDragConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            v.window?.isMovableByWindowBackground = true
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Library hub (Photos / Favorites / Collections / Generate / Live)

private struct LibraryHubView: View {
    enum Page: String, CaseIterable, Identifiable {
        case photos = "Photos", favorites = "Favorites", collections = "Collections"
        case generate = "Generate", live = "Live"
        var id: String { rawValue }
    }
    @State private var page: Page = .photos
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rotation: RotationManager

    var body: some View {
        VStack(spacing: 16) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            GlassSegmentBar(items: Page.allCases, label: \.rawValue,
                            selection: $page, itemWidth: 104)
            Spacer()
            if page == .photos && library.folderURL != nil {
                Button { rotation.rotateNow() } label: { Label("Shuffle", systemImage: "shuffle") }
                    .buttonStyle(.glass)
                Button { library.chooseFolder() } label: { Label("Choose Folder", systemImage: "folder") }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 70)
    }

    // Each page scrolls itself (Generate/Live already contain a ScrollView).
    @ViewBuilder
    private var content: some View {
        switch page {
        case .photos:
            if library.folderURL == nil {
                ScrollView { EmptyFolderCard() }
            } else if library.images.isEmpty {
                ContentUnavailableView("No images here", systemImage: "photo",
                    description: Text("This folder has no images. Pick another."))
            } else {
                ScrollView { WallpaperGrid(urls: library.images) }
            }
        case .favorites:
            if library.favoriteURLs.isEmpty {
                ContentUnavailableView("No favorites yet", systemImage: "heart",
                    description: Text("Hover any wallpaper and tap the heart."))
            } else {
                ScrollView { WallpaperGrid(urls: library.favoriteURLs) }
            }
        case .collections:
            CollectionsPage()
        case .generate:
            GenerateView()
        case .live:
            LiveView()
        }
    }
}

private struct CollectionsPage: View {
    @EnvironmentObject private var collections: CollectionStore
    @State private var selected: UUID?
    @State private var newName = ""
    @State private var creating = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Menu {
                    ForEach(collections.collections) { c in
                        Button(c.name) { selected = c.id }
                    }
                } label: {
                    Label(currentName, systemImage: "rectangle.stack")
                }
                .buttonStyle(.glass)
                Button { creating = true } label: { Label("New", systemImage: "plus") }
                    .buttonStyle(.glassProminent)
                Spacer()
            }
            .padding(.horizontal, 24)

            if let id = selected ?? collections.collections.first?.id,
               let c = collections.collections.first(where: { $0.id == id }), !c.urls.isEmpty {
                ScrollView { WallpaperGrid(urls: c.urls) }
            } else {
                ContentUnavailableView("No wallpapers", systemImage: "rectangle.stack",
                    description: Text("Right-click any wallpaper → Add to collection."))
                    .padding(.top, 60)
                Spacer()
            }
        }
        .alert("New Collection", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Create") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { collections.addCollection(named: n) }
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
    }

    private var currentName: String {
        let id = selected ?? collections.collections.first?.id
        return collections.collections.first { $0.id == id }?.name ?? "Collections"
    }
}

struct EmptyFolderCard: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Pick a folder of images").font(.title2.weight(.semibold))
                Text("Browse your photos and set any one as your desktop wallpaper.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                Button { library.chooseFolder() } label: {
                    Label("Choose Folder", systemImage: "folder")
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
            }
            .padding(48)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
        .padding(.top, 60)
    }
}
