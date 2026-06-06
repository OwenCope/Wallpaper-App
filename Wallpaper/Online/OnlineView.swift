import SwiftUI

/// The Explore tab — search Wallhaven and browse results in a grid.
struct ExploreView: View {
    @Binding var query: String
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rotation: RotationManager
    @EnvironmentObject private var collections: CollectionStore
    @EnvironmentObject private var preview: PreviewCoordinator
    @AppStorage("wallhaven.apiKey") private var apiKey = ""

    @State private var field = ""
    @State private var photos: [WallhavenPhoto] = []
    @State private var page = 1
    @State private var lastPage = 1
    @State private var loading = false
    @State private var errorText: String?
    @State private var busyID: String?
    @State private var loadedFor = ""

    private var service: WallhavenService { WallhavenService(apiKey: apiKey.isEmpty ? nil : apiKey) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                searchField
                content
            }
            .padding(.top, 78)
            .padding(.bottom, 30)
        }
        .onAppear {
            field = query
            if loadedFor != query { Task { await runSearch() } }
        }
        .onChange(of: query) { _, new in
            field = new
            Task { await runSearch() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search wallpapers…", text: $field)
                .textFieldStyle(.plain)
                .onSubmit { query = field; Task { await runSearch() } }
            if !field.isEmpty {
                Button { field = ""; query = ""; Task { await runSearch() } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 520)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var content: some View {
        if let errorText {
            ContentUnavailableView("Couldn't load", systemImage: "wifi.exclamationmark",
                description: Text(errorText)).padding(.top, 40)
        } else if photos.isEmpty && !loading {
            ContentUnavailableView("Nothing here", systemImage: "globe",
                description: Text("Try “nature”, “minimal”, “space”…")).padding(.top, 40)
        } else {
            LazyVGrid(columns: .wallpaperColumns, spacing: 18) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    WallpaperCard(
                        image: { remoteImage(photo) },
                        caption: photo.resolution,
                        isBusy: busyID == photo.id,
                        onSet: { preview.present(.remote(photo, service: service, library: library)) }
                    )
                    .contextMenu { menu(photo) }
                    .onAppear {
                        // Prefetch the next page once we're within the last row or two.
                        if index >= photos.count - 6 { Task { await loadMore() } }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        if loading { ProgressView().padding(.vertical, 30) }
    }

    @ViewBuilder
    private func menu(_ photo: WallhavenPhoto) -> some View {
        Button("Set as wallpaper") { Task { await setWallpaper(photo) } }
        if !collections.collections.isEmpty {
            Menu("Download to collection") {
                ForEach(collections.collections) { c in
                    Button(c.name) { Task { await download(photo, into: c.id) } }
                }
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

    // MARK: - Actions

    private func runSearch() async {
        page = 1; loadedFor = query
        SearchHistory.record(query)
        await fetch(reset: true)
    }

    private func loadMore() async {
        guard !loading, page < lastPage else { return }
        page += 1
        await fetch(reset: false)
    }

    private func fetch(reset: Bool) async {
        loading = true; errorText = nil
        defer { loading = false }
        do {
            let sorting = query.trimmingCharacters(in: .whitespaces).isEmpty ? "toplist" : "relevance"
            let result = try await service.search(query: query, page: page, sorting: sorting)
            lastPage = result.meta?.last_page ?? 1
            if reset { photos = result.data } else { photos.append(contentsOf: result.data) }
        } catch { errorText = friendly(error) }
    }

    private func setWallpaper(_ photo: WallhavenPhoto) async {
        busyID = photo.id; defer { busyID = nil }
        do {
            let local = try await service.download(photo)
            library.setWallpaper(local, allScreens: rotation.allScreens)
        } catch { errorText = friendly(error) }
    }

    private func download(_ photo: WallhavenPhoto, into id: UUID) async {
        busyID = photo.id; defer { busyID = nil }
        if let local = try? await service.download(photo) { collections.add(local, to: id) }
    }

    private func friendly(_ error: Error) -> String {
        switch error {
        case WallhavenError.http(429):
            return "Rate limited. Add a Wallhaven API key in Settings."
        case WallhavenError.http(let code): return "Server returned \(code)."
        default: return error.localizedDescription
        }
    }
}
