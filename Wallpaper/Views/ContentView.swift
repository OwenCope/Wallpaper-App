import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case explore = "Explore"
    case library = "Library"
    case minecraft = "Minecraft"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var collections: CollectionStore
    @EnvironmentObject private var preview: PreviewCoordinator
    @State private var tab: AppTab = .home
    @State private var exploreQuery = ""
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            // Content scrolls underneath the floating toolbar.
            Group {
                switch tab {
                case .home:    HomeView(tab: $tab, exploreQuery: $exploreQuery)
                case .explore: ExploreView(query: $exploreQuery)
                case .library: LibraryHubView()
                case .minecraft: MinecraftView()
                }
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
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - Floating top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Wordmark (top-left) — matches the app icon.
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        LinearGradient(colors: [Color(red: 0.36, green: 0.32, blue: 0.95),
                                                Color(red: 0.62, green: 0.28, blue: 0.95),
                                                Color(red: 0.92, green: 0.36, blue: 0.66)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 7))
                Text("Wallpaper").font(.headline.weight(.semibold))
            }

            Spacer()

            // Centered segmented control + search.
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    segmentedTabs
                    circleButton("magnifyingglass") { tab = .explore }
                }
            }

            Spacer()

            // Right-side actions.
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    circleButton("plus") { tab = .library }
                    circleButton("gearshape") { showSettings = true }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var segmentedTabs: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { t in
                Button { tab = t } label: {
                    Text(t.rawValue)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(tab == t ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background {
                            if tab == t {
                                Capsule().fill(.white.opacity(0.18))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
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
        VStack(spacing: 14) {
            Picker("", selection: $page) {
                ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 480)
            .padding(.top, 70)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
                ScrollView {
                    HStack {
                        Spacer()
                        Button { rotation.rotateNow() } label: { Label("Shuffle", systemImage: "shuffle") }
                            .buttonStyle(.glass)
                        Button { library.chooseFolder() } label: { Label("Choose Folder", systemImage: "folder") }
                            .buttonStyle(.glassProminent)
                    }
                    .padding(.horizontal, 24)
                    WallpaperGrid(urls: library.images)
                }
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
