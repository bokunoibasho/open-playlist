import Foundation

/// Fetches lightweight display metadata for a saved Track (Phase 8 / Issue #26).
/// Uses YouTube's public **oEmbed** endpoint to get the channel name (author) —
/// and a cleaner title — without scraping the page or logging in. Best-effort:
/// any failure resolves to `nil` and the artist line simply stays hidden. Returns
/// `nil` for non-YouTube sources (oEmbed there isn't available).
enum MetadataService {
    struct Metadata: Sendable {
        var title: String?
        var author: String?
    }

    /// oEmbed lookup for a YouTube watch page. `pageURL` must be the watch page
    /// (never a stream URL). Network / parse / non-2xx all resolve to `nil` so
    /// enrichment never blocks or breaks adding a track.
    static func fetchYouTube(for pageURL: URL) async -> Metadata? {
        guard var components = URLComponents(string: "https://www.youtube.com/oembed") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: pageURL.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let endpoint = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(OEmbedResponse.self, from: data)
            return Metadata(title: decoded.title, author: decoded.authorName)
        } catch {
            return nil
        }
    }

    private struct OEmbedResponse: Decodable {
        let title: String?
        let authorName: String?

        enum CodingKeys: String, CodingKey {
            case title
            case authorName = "author_name"
        }
    }
}
