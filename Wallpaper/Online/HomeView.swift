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

    private let heroTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var service: WallhavenService { WallhavenService(apiKey: apiKey.isEmpty ? nil : apiKey) }

    struct Category: Identifiable {
        let id = UUID(); let name: String; let query: String; let colors: [Color]
    }
    private let categories: [Category] = [
        .init(name: "Nature", query: "nature landscape", colors: [.green, .teal]),
        .init(name: "Anime", query: "anime", colors: [.pink, .purple]),
        .init(name: "Minimal", query: "minimal", colors: [.gray, .black]),
        .init(name: "Space", query: "space galaxy", colors: [.indigo, .black]),
        .init(name: "Cars", query: "cars", colors: [.red, .orange]),
        .init(name: "City", query: "city night", colors: [.blue, .indigo]),
        .init(name: "Minecraft", query: "minecraft", colors: [.green, .brown]),
        .init(name: "Gaming", query: "video games", colors: [.purple, .blue]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroBanner   // full-bleed, toolbar floats over it
                VStack(alignment: .leading, spacing: 64) {
                    carousel(title: "Most recent community wallpapers", subtitle: nil,
                             photos: latest, ranked: false)
                    carousel(title: "Most Popular Wallpapers",
                             subtitle: "Trending wallpapers loved by the community",
                             photos: popular, ranked: true)
                    carousel(title: "4K Ultra HD",
                             subtitle: "Crisp wallpapers for high-resolution displays",
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
                AsyncImage(url: URL(string: photo.thumbs.large)) { img in
                    img.resizable().scaledToFill()
                } placeholder: { Rectangle().fill(.quaternary) }
                .frame(maxWidth: .infinity).frame(height: 480).clipped()
                .id(heroIndex)
                .transition(.opacity)

                // Cinematic scrim so text reads over any image.
                LinearGradient(colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)

                // Auto-rotate page dots (top-right).
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(0..<min(hero.count, 8), id: \.self) { i in
                                Capsule().fill(.white.opacity(i == heroIndex % hero.count ? 0.95 : 0.4))
                                    .frame(width: i == heroIndex % hero.count ? 20 : 6, height: 6)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                    }
                    Spacer()
                }
                .padding(.top, 70).padding(.horizontal, 40)

                // FEATURED · title · metadata · actions (bottom-left).
                VStack(alignment: .leading, spacing: 10) {
                    Text("FEATURED")
                        .font(.caption.weight(.bold)).tracking(3)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(title)
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.white)
                    HStack(spacing: 14) {
                        if !heroQuery.isEmpty { metaTag(heroQuery.capitalized) }
                        metaTag(photo.resolution)
                        if let bytes = photo.file_size, bytes > 0 { metaTag(byteString(bytes)) }
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    HStack(spacing: 12) {
                        Button { preview.present(.remote(photo, service: service, library: library)) } label: {
                            Label("View Wallpaper", systemImage: "arrow.up.forward")
                                .font(.callout.weight(.semibold))
                                .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                        Button { Task { await setWallpaper(photo) } } label: {
                            Image(systemName: "heart.fill").foregroundStyle(.pink)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .padding(.top, 6)
                }
                .padding(.leading, 40).padding(.bottom, 40)
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
                        Button {
                            exploreQuery = cat.query
                            tab = .explore
                        } label: {
                            LinearGradient(colors: cat.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(width: 260, height: 150)
                                .overlay(alignment: .bottomLeading) {
                                    Text(cat.name)
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(14)
                                }
                                .clipShape(.rect(cornerRadius: Theme.cornerRadius))
                        }
                        .buttonStyle(.plain)
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
        async let latestR = try? service.search(query: "", page: 1, sorting: "date_added")
        async let popularR = try? service.search(query: "", page: 1, sorting: "toplist")
        async let fourKR = try? service.search(query: "", page: 1, atleast: "3840x2160", sorting: "toplist")
        heroQuery = SearchHistory.recent.first ?? ""
        async let heroR = try? service.search(query: heroQuery, page: 1,
                                              sorting: heroQuery.isEmpty ? "toplist" : "relevance")
        latest = (await latestR)?.data ?? []
        popular = (await popularR)?.data ?? []
        fourK = (await fourKR)?.data ?? []
        hero = (await heroR)?.data ?? []
        loading = false
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
