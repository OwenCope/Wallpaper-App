import SwiftUI
import UniformTypeIdentifiers

/// Owns the user's local wallpaper folder, the discovered images, and favorites.
@MainActor
final class LibraryStore: ObservableObject {
    @Published var folderURL: URL?
    @Published private(set) var images: [URL] = []
    @Published var favorites: Set<String> = []
    @Published var currentWallpaper: URL?

    private let defaults = UserDefaults.standard
    private let folderKey = "library.folderBookmark"
    private let favoritesKey = "library.favorites"

    private static let imageExtensions: Set<String> =
        ["jpg", "jpeg", "png", "heic", "heif", "tiff", "gif", "bmp"]

    init() {
        favorites = Set(defaults.stringArray(forKey: favoritesKey) ?? [])
        restoreFolder()
    }

    // MARK: - Folder selection

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFolder(url)
    }

    func setFolder(_ url: URL) {
        folderURL = url
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            defaults.set(bookmark, forKey: folderKey)
        }
        reload()
    }

    private func restoreFolder() {
        guard let data = defaults.data(forKey: folderKey) else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale) {
            _ = url.startAccessingSecurityScopedResource()
            folderURL = url
            reload()
        }
    }

    func reload() {
        guard let folderURL else { images = []; return }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        images = contents
            .filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: - Favorites

    func isFavorite(_ url: URL) -> Bool { favorites.contains(url.path) }

    func toggleFavorite(_ url: URL) {
        if favorites.contains(url.path) { favorites.remove(url.path) }
        else { favorites.insert(url.path) }
        defaults.set(Array(favorites), forKey: favoritesKey)
    }

    var favoriteURLs: [URL] {
        images.filter { favorites.contains($0.path) }
    }

    // MARK: - Setting wallpaper

    func setWallpaper(_ url: URL, allScreens: Bool = true) {
        if allScreens { WallpaperManager.setOnAllScreens(url) }
        else { WallpaperManager.setOnMainScreen(url) }
        currentWallpaper = url
    }

    func randomImage(favoritesOnly: Bool) -> URL? {
        let pool = favoritesOnly ? favoriteURLs : images
        return pool.randomElement()
    }
}
