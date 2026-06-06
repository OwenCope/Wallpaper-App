import SwiftUI

struct WallpaperCollection: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var imagePaths: [String] = []   // absolute file paths

    var urls: [URL] { imagePaths.map { URL(fileURLWithPath: $0) } }
}

/// User-defined collections of wallpapers (local files or downloaded ones).
@MainActor
final class CollectionStore: ObservableObject {
    @Published private(set) var collections: [WallpaperCollection] = []

    private var fileURL: URL { AppPaths.support.appendingPathComponent("collections.json") }

    init() { load() }

    func addCollection(named name: String) {
        collections.append(WallpaperCollection(name: name))
        save()
    }

    func delete(_ collection: WallpaperCollection) {
        collections.removeAll { $0.id == collection.id }
        save()
    }

    func add(_ url: URL, to id: UUID) {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        if !collections[idx].imagePaths.contains(url.path) {
            collections[idx].imagePaths.append(url.path)
            save()
        }
    }

    func remove(_ url: URL, from id: UUID) {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[idx].imagePaths.removeAll { $0 == url.path }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([WallpaperCollection].self, from: data)
        else { return }
        collections = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(collections) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
