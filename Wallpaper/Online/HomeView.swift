import SwiftUI

/// Tracks the user's recent Explore searches (used to personalize the Home hero).
enum SearchHistory {
    private static let key = "search.history"
    static func record(_ query: String) {
        let t = query.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0.caseInsensitiveCompare(t) == .orderedSame }
        list.insert(t, at: 0)
        UserDefaults.standard.set(Array(list.prefix(10)), forKey: key)
    }
    static var recent: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
}

/// The landing page — horizontal carousels of community wallpapers plus
/// category shortcuts, mirroring Wallspace's Home tab.
struct HomeView: View {
    @Binding var tab: AppTab
    @Binding var exploreQuery: String
    @AppStorage("wallhaven.apiKey") private var apiKey = ""
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rotation: RotationManager
    @EnvironmentObject private var preview: PreviewCoordinator

    @State private var latest: [WallhavenPhoto] = []
    @State private var popular: [WallhavenPhoto] = []
    @State private var fourK: [WallhavenPhoto] = []
    @State private var hero: [WallhavenPhoto] = []
    @State private var heroIndex = 0
    @State private var heroQuery = ""
    @State private var loading = true
    @State private var busyID: String?
    @State private var favoritedHeroIDs: Set<String> = []

    private let heroTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var service: WallhavenService { WallhavenService(apiKey: apiKey.isEmpty ? nil : apiKey) }

    struct Category: Identifiable {
        let id = UUID(); let name: String; let query: String; let colors: [Color]
    }
    private let categories: [Category] = [
        .init(name: "Nature", query: "nature landscape", colors: [.green, .teal]),
        .init(name: "Animals", query: "animals wildlife", colors: [.orange, .brown]),
        .init(name: "Tech", query: "technology computer setup", colors: [.blue, .indigo]),
        .init(name: "Space", query: "space galaxy", colors: [.indigo, .black]),
        .init(name: "Minimal", query: "minimal", colors: [.gray, .black]),
        .init(name: "Mountains", query: "mountains", colors: [.teal, .gray]),
        .init(name: "Ocean", query: "ocean beach", colors: [.cyan, .blue]),
        .init(name: "Forest", query: "forest", colors: [.green, .black]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroBanner   // full-bleed, toolbar floats over it
                VStack(alignment: .leading, spacing: 64) {
                    carousel(title: "Nature",
                             subtitle: "Landscapes, forests & mountains",
                             photos: latest, ranked: false)
                    carousel(title: "Pets & Animals",
                             subtitle: "Cats, dogs & wildlife",
                             photos: popular, ranked: false)
                    carousel(title: "Tech & Setups",
                             subtitle: "Gadgets, desks & gear",
                             photos: fourK, ranked: false)
                    categoriesSection
                }
                .padding(.top, 34)
                .padding(.bottom, 60)
            }
        }
        .ignoresSafeArea(edges: .top)
        .task { await load() }
        .onReceive(heroTimer) { _ in
            guard hero.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.6)) { heroIndex = (heroIndex + 1) % hero.count }
        }
    }

    // MARK: - Featured hero (auto-rotating, personalized by search history)

    @ViewBuilder
    private var heroBanner: some View {
        if !hero.isEmpty {
            let photo = hero[heroIndex % hero.count]
            let title = heroQuery.isEmpty ? "Featured" : heroQuery.capitalized
            ZStack(alignment: .bottomLeading) {
                // Thumb loads instantly; the full-resolution image fades in
                // on top so the hero is never blurry once loaded.
                ZStack {
                    AsyncImage(url: URL(string: photo.thumbs.large)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: { Rectangle().fill(.quaternary) }
                    AsyncImage(url: URL(string: photo.path)) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                                .transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 480).clipped()
                .id(heroIndex)
                .transition(.opacity)

                // Cinematic scrim so text reads over any image.
                LinearGradient(colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)

                // FEATURED · title · metadata · actions (bottom-left) + page dots (bottom-right).
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FEATURED")
                            .font(.caption.weight(.bold)).tracking(3)
                            .foregroundStyle(.white.opacity(0.85))
                        Text(title)
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(.white)
                        HStack(spacing: 14) {
                            metaTag(photo.resolution)
                            if let bytes = photo.file_size, bytes > 0 { metaTag(byteString(bytes)) }
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        HStack(spacing: 12) {
                            Button { preview.present(.remote(photo, service: service, library: library)) } label: {
                                Label("View Wallpaper", systemImage: "arrow.up.forward")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            Button { Task { await favorite(photo) } } label: {
                                Image(systemName: favoritedHeroIDs.contains(photo.id) ? "heart.fill" : "heart")
                                    .foregroundStyle(.pink)
                                    .frame(width: 40, height: 40)
                                    .contentShape(.circle)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .help("Save to Favorites")
                        }
                        .padding(.top, 6)
                    }
                    Spacer()
                    // Page dots, bottom-right (clear of the toolbar).
                    HStack(spacing: 6) {
                        ForEach(0..<min(hero.count, 8), id: \.self) { i in
                            Capsule().fill(.white.opacity(i == heroIndex % hero.count ? 0.95 : 0.4))
                                .frame(width: i == heroIndex % hero.count ? 20 : 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                }
                .padding(.horizontal, 40).padding(.bottom, 40)
            }
            .frame(height: 480)
            .contentShape(.rect)
        }
    }

    private func metaTag(_ s: String) -> some View {
        Text(s).font(.subheadline.weight(.medium))
    }

    private func byteString(_ bytes: Int) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    private func setWallpaper(_ photo: WallhavenPhoto) async {
        busyID = photo.id; defer { busyID = nil }
        if let local = try? await service.download(photo) {
            library.setWallpaper(local, allScreens: rotation.allScreens)
        }
    }

    /// Download the photo and add it to Favorites (the hero's heart button).
    private func favorite(_ photo: WallhavenPhoto) async {
        guard !favoritedHeroIDs.contains(photo.id) else { return }
        if let local = try? await service.download(photo) {
            library.toggleFavorite(local)
            favoritedHeroIDs.insert(photo.id)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func carousel(title: String, subtitle: String?, photos: [WallhavenPhoto], ranked: Bool) -> some View {
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: title, subtitle: subtitle)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(Array(photos.prefix(12).enumerated()), id: \.element.id) { idx, photo in
                            WallpaperCard(
                                image: { remoteImage(photo) },
                                badge: photo.resolution.hasPrefix("3840") || photo.resolution.hasPrefix("7680") ? "4K" : nil,
                                rank: ranked ? idx + 1 : nil,
                                height: 210,
                                isBusy: busyID == photo.id,
                                onSet: { preview.present(.remote(photo, service: service, library: library)) }
                            )
                            .frame(width: 360)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Categories", subtitle: "Browse wallpapers by category")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(categories) { cat in
                        CategoryTile(category: cat) {
                            exploreQuery = cat.query
                            tab = .explore
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private func remoteImage(_ photo: WallhavenPhoto) -> some View {
        AsyncImage(url: URL(string: photo.thumbs.large)) { phase in
            switch phase {
            case .success(let image): image.resizable()
            default: Rectangle().fill(.quaternary).overlay(ProgressView().controlSize(.small))
            }
        }
    }

    // MARK: - Data

    private func load() async {
        loading = true
        async let latestR = try? service.search(query: "nature landscape", page: 1, sorting: "toplist")
        async let popularR = try? service.search(query: "animals pets wildlife", page: 1, sorting: "toplist")
        async let fourKR = try? service.search(query: "technology computer setup", page: 1, sorting: "toplist")
        async let heroPhotos = personalizedHero()
        latest = (await latestR)?.data ?? []
        popular = (await popularR)?.data ?? []
        fourK = (await fourKR)?.data ?? []
        hero = await heroPhotos
        heroIndex = 0
        loading = false
    }

    /// Blend the user's recent searches into the Featured rotation instead of
    /// only echoing the single latest one. Results are interleaved so each
    /// interest shows up as the hero cycles, deduped by photo id.
    private func personalizedHero() async -> [WallhavenPhoto] {
        let recents = Array(SearchHistory.recent.prefix(3))
        guard !recents.isEmpty else {
            heroQuery = ""
            return (try? await service.search(query: "nature", sorting: "relevance"))?.data ?? []
        }
        heroQuery = recents.count == 1 ? recents[0] : "For You"

        let buckets: [[WallhavenPhoto]] = await withTaskGroup(of: (Int, [WallhavenPhoto]).self) { group in
            for (i, query) in recents.enumerated() {
                group.addTask {
                    (i, (try? await service.search(query: query, sorting: "relevance"))?.data ?? [])
                }
            }
            var out = [[WallhavenPhoto]](repeating: [], count: recents.count)
            for await (i, photos) in group { out[i] = photos }
            return out
        }

        // Interleave: best of search 1, best of search 2, … then second-best, etc.
        var mixed: [WallhavenPhoto] = []
        var seen = Set<String>()
        for rank in 0..<(buckets.map(\.count).max() ?? 0) {
            for bucket in buckets where rank < bucket.count {
                let photo = bucket[rank]
                if seen.insert(photo.id).inserted { mixed.append(photo) }
            }
        }
        return Array(mixed.prefix(12))
    }
}

/// A category tile with a hover lift + brightening.
private struct CategoryTile: View {
    let category: HomeView.Category
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            LinearGradient(colors: category.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 260, height: 150)
                .overlay(alignment: .bottomLeading) {
                    Text(category.name).font(.title3.weight(.bold)).foregroundStyle(.white).padding(14)
                }
                .overlay { Color.white.opacity(hovering ? 0.12 : 0) }
                .clipShape(.rect(cornerRadius: Theme.cornerRadius))
                .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(.white.opacity(hovering ? 0.5 : 0), lineWidth: 1.5) }
                .shadow(color: .black.opacity(hovering ? 0.3 : 0.15), radius: hovering ? 14 : 7, y: hovering ? 8 : 4)
                .scaleEffect(hovering ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// Reusable "Title + gray subtitle" section header.
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.weight(.bold))
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
    }
}
