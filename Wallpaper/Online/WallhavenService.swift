import Foundation

// MARK: - API models (only the fields we use)

struct WallhavenSearchResponse: Decodable {
    let data: [WallhavenPhoto]
    let meta: Meta?
    struct Meta: Decodable {
        let current_page: Int
        let last_page: Int
        let total: Int
    }
}

struct WallhavenPhoto: Decodable, Identifiable, Hashable {
    let id: String
    let url: String          // page URL
    let path: String         // full-resolution image URL
    let resolution: String
    let file_size: Int?      // bytes
    let thumbs: Thumbs
    struct Thumbs: Decodable, Hashable {
        let large: String
        let small: String
    }
}

enum WallhavenError: Error { case badURL, http(Int), decode }

/// Talks to the Wallhaven REST API. No key needed for SFW browsing;
/// a key (if present) raises rate limits and unlocks NSFW/your collections.
struct WallhavenService {
    var apiKey: String? = nil

    /// purity/categories are 3-bit strings, e.g. "100" = general / sfw only.
    func search(query: String,
                page: Int = 1,
                categories: String = "111",
                purity: String = "100",
                atleast: String? = "1920x1080",
                sorting: String = "toplist") async throws -> WallhavenSearchResponse {
        var comps = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        var items: [URLQueryItem] = [
            .init(name: "categories", value: categories),
            .init(name: "purity", value: purity),
            .init(name: "sorting", value: sorting),
            .init(name: "page", value: String(page))
        ]
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            items.append(.init(name: "q", value: query))
        }
        if let atleast { items.append(.init(name: "atleast", value: atleast)) }
        if let apiKey, !apiKey.isEmpty { items.append(.init(name: "apikey", value: apiKey)) }
        comps.queryItems = items

        guard let url = comps.url else { throw WallhavenError.badURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WallhavenError.http(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(WallhavenSearchResponse.self, from: data)
        } catch {
            throw WallhavenError.decode
        }
    }

    /// Fetch a photo's tags (the detail endpoint includes them; search does not)
    /// and build a human-friendly title from the top tags, e.g. "Autumn · Mount Fuji".
    func title(for photo: WallhavenPhoto) async -> String? {
        struct Detail: Decodable {
            let data: Inner
            struct Inner: Decodable { let tags: [Tag]? }
            struct Tag: Decodable { let name: String }
        }
        var comps = URLComponents(string: "https://wallhaven.cc/api/v1/w/\(photo.id)")!
        if let apiKey, !apiKey.isEmpty { comps.queryItems = [.init(name: "apikey", value: apiKey)] }
        guard let url = comps.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let detail = try? JSONDecoder().decode(Detail.self, from: data),
              let tags = detail.data.tags, !tags.isEmpty else { return nil }
        let names = tags.prefix(2).map(\.name.localizedCapitalized)
        return names.joined(separator: " · ")
    }

    /// Download the full-resolution file into the app's cache and return the local URL.
    func download(_ photo: WallhavenPhoto) async throws -> URL {
        guard let remote = URL(string: photo.path) else { throw WallhavenError.badURL }
        let (tmp, response) = try await URLSession.shared.download(from: remote)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WallhavenError.http(http.statusCode)
        }
        let ext = remote.pathExtension.isEmpty ? "jpg" : remote.pathExtension
        let dest = AppPaths.downloads.appendingPathComponent("wallhaven-\(photo.id).\(ext)")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }
}

/// Central place for the app's on-disk folders.
enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    static var downloads: URL { subdir("Downloads") }
    static var generated: URL { subdir("Generated") }

    private static func subdir(_ name: String) -> URL {
        let dir = support.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
