import SwiftUI

/// Reusable thumbnail grid for local file URLs, with favorite + set actions.
struct WallpaperGrid: View {
    let urls: [URL]
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rotation: RotationManager
    @EnvironmentObject private var collections: CollectionStore
    @EnvironmentObject private var preview: PreviewCoordinator

    var body: some View {
        LazyVGrid(columns: .wallpaperColumns, spacing: 18) {
            ForEach(urls, id: \.self) { url in
                WallpaperCard(
                    image: { AsyncImageFile(url: url) },
                    isFavorite: library.isFavorite(url),
                    isCurrent: library.currentWallpaper == url,
                    onSet: { preview.present(.local(url, library: library)) },
                    onFavorite: { library.toggleFavorite(url) }
                )
                .contextMenu { contextMenu(for: url) }
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private func contextMenu(for url: URL) -> some View {
        Button("Set on all displays") { library.setWallpaper(url, allScreens: true) }
        Button("Set on this display") { library.setWallpaper(url, allScreens: false) }
        Divider()
        Button(library.isFavorite(url) ? "Remove favorite" : "Add to favorites") {
            library.toggleFavorite(url)
        }
        if !collections.collections.isEmpty {
            Menu("Add to collection") {
                ForEach(collections.collections) { c in
                    Button(c.name) { collections.add(url, to: c.id) }
                }
            }
        }
    }
}
