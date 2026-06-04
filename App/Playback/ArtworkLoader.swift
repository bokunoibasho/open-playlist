import UIKit

/// Loads cover art for the large surfaces (full-screen audio art, lock screen),
/// preferring the high-res `maxresdefault` and falling back to `mqdefault`. The
/// HD variant 404s for non-HD uploads — and that 404 *still* returns a tiny valid
/// JPEG, so we must check the HTTP status, not just whether the data decodes (#48).
enum ArtworkLoader {
    static func load(highRes: URL?, fallback: URL?) async -> UIImage? {
        if let highRes, let image = await image(from: highRes) { return image }
        if let fallback { return await image(from: fallback) }
        return nil
    }

    private static func image(from url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data)
        else { return nil }
        return image
    }
}
