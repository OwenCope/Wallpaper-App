import AppKit

/// Fetches a Minecraft player's skin texture by username.
enum SkinService {
    enum SkinError: LocalizedError {
        case notFound, network
        var errorDescription: String? {
            switch self {
            case .notFound: "No player found with that username."
            case .network: "Couldn't reach the skin server."
            }
        }
    }

    /// Returns the raw skin PNG (64×64, or legacy 64×32) for a username.
    static func skin(for username: String) async throws -> NSImage {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "https://minotar.net/skin/\(name)") else {
            throw SkinError.notFound
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                throw SkinError.notFound
            }
            guard let image = NSImage(data: data) else { throw SkinError.notFound }
            return image
        } catch let e as SkinError {
            throw e
        } catch {
            throw SkinError.network
        }
    }
}
