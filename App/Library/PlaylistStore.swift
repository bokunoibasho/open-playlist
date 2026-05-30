import Foundation
import SwiftData

/// Domain-layer operations over playlists (DESIGN.md §3). Wraps a `ModelContext`
/// so views stay thin and the `DetectedStream`→`Track` mapping lives in one place.
@MainActor
struct PlaylistStore {
    let context: ModelContext

    @discardableResult
    func createPlaylist(name: String) -> Playlist {
        let playlist = Playlist(name: name)
        context.insert(playlist)
        return playlist
    }

    /// Converts a detected stream into a Track and appends it to the playlist.
    /// `pageURL` is the browser's current page URL — the authoritative source for
    /// the watch page (see `makeTrack`).
    func add(_ stream: DetectedStream, to playlist: Playlist, pageURL: URL? = nil) {
        let track = Self.makeTrack(from: stream, position: playlist.tracks.count, pageURL: pageURL)
        context.insert(track)
        track.playlist = playlist
        enrichMetadata(for: track)
    }

    /// Fills in the artist (and a cleaner title) shortly after adding, so the
    /// add itself stays instant (Phase 8 / Issue #26). Only YouTube watch pages
    /// expose oEmbed; everything else keeps the blank author line. Failures are
    /// silent — this is display polish, not correctness.
    func enrichMetadata(for track: Track) {
        guard track.author == nil,
              Self.youTubeVideoID(from: track.sourceURL) != nil else { return }
        let sourceURL = track.sourceURL
        let context = self.context
        // Explicit @MainActor hop (consistent with Issue #21): mutate the model
        // and save on the main actor after the network await resumes.
        Task { @MainActor in
            guard let meta = await MetadataService.fetchYouTube(for: sourceURL),
                  track.modelContext != nil else { return }
            if let author = Self.normalizeAuthor(meta.author) {
                track.author = author
            }
            if track.title == "(無題)", let title = meta.title, !title.isEmpty {
                track.title = title
            }
            try? context.save()
        }
    }

    func move(in playlist: Playlist, from source: IndexSet, to destination: Int) {
        var ordered = playlist.orderedTracks
        ordered.move(fromOffsets: source, toOffset: destination)
        reindex(ordered)
    }

    func delete(_ track: Track) {
        Self.removeLocalFile(for: track)
        let playlist = track.playlist
        context.delete(track)
        if let playlist {
            reindex(playlist.orderedTracks.filter { $0 !== track })
        }
    }

    func delete(_ playlist: Playlist) {
        // Cascade deletes the Track objects, but not their downloaded files.
        for track in playlist.tracks { Self.removeLocalFile(for: track) }
        context.delete(playlist)
    }

    private func reindex(_ tracks: [Track]) {
        for (index, track) in tracks.enumerated() {
            track.position = index
        }
    }

    private static func removeLocalFile(for track: Track) {
        guard let url = track.localFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Mapping

    static func makeTrack(from stream: DetectedStream, position: Int, pageURL: URL? = nil) -> Track {
        // `sourceURL` is the re-resolution key (Phase 5) — it must be the *page*,
        // never the stream URL. `stream.src` is a short-lived media URL (e.g.
        // googlevideo…); storing it loses the videoID and crashes the re-resolve
        // path (Issue #16). Prefer the browser's current URL, then the script's
        // reported page; among those, favour one we can extract a providerID from.
        let candidates = [pageURL, stream.pageSrc.flatMap { URL(string: $0) }]
            .compactMap { $0 }
            .filter(isWebPage)
        let sourceURL = candidates.first { youTubeVideoID(from: $0) != nil }
            ?? candidates.first
            ?? URL(string: "about:blank")!
        let providerID = youTubeVideoID(from: sourceURL)
        let thumbnailURL = providerID.flatMap {
            URL(string: "https://img.youtube.com/vi/\($0)/hqdefault.jpg")
        }
        return Track(
            sourceURL: sourceURL,
            providerID: providerID,
            title: bestTitle(for: stream),
            durationSeconds: stream.duration,
            thumbnailURL: thumbnailURL,
            position: position
        )
    }

    /// Tidies a channel/artist name: trims whitespace and drops YouTube's
    /// auto-generated " - Topic" art-track suffix (Issue #26).
    static func normalizeAuthor(_ name: String?) -> String? {
        guard var trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix(" - Topic") {
            trimmed = String(trimmed.dropLast(" - Topic".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isWebPage(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    static func bestTitle(for stream: DetectedStream) -> String {
        if let name = stream.name, !name.isEmpty { return name }
        if let pageTitle = stream.pageTitle, !pageTitle.isEmpty { return pageTitle }
        return "(無題)"
    }

    /// Extracts a YouTube video ID from a page URL, handling watch?v=, youtu.be/,
    /// and /shorts//embed/ forms. Used as the re-resolution key in Phase 5.
    static func youTubeVideoID(from url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }

        if host.contains("youtu.be") {
            let id = url.lastPathComponent
            return id.isEmpty || id == "/" ? nil : id
        }

        guard host.contains("youtube.com") else { return nil }

        let parts = url.pathComponents
        if let idx = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" }),
           idx + 1 < parts.count {
            return parts[idx + 1]
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first { $0.name == "v" }?.value
    }
}
