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
    func add(_ stream: DetectedStream, to playlist: Playlist) {
        let track = Self.makeTrack(from: stream, position: playlist.tracks.count)
        context.insert(track)
        track.playlist = playlist
    }

    func move(in playlist: Playlist, from source: IndexSet, to destination: Int) {
        var ordered = playlist.orderedTracks
        ordered.move(fromOffsets: source, toOffset: destination)
        reindex(ordered)
    }

    func delete(_ track: Track) {
        let playlist = track.playlist
        context.delete(track)
        if let playlist {
            reindex(playlist.orderedTracks.filter { $0 !== track })
        }
    }

    func delete(_ playlist: Playlist) {
        context.delete(playlist)
    }

    private func reindex(_ tracks: [Track]) {
        for (index, track) in tracks.enumerated() {
            track.position = index
        }
    }

    // MARK: - Mapping

    static func makeTrack(from stream: DetectedStream, position: Int) -> Track {
        let pageString = stream.pageSrc ?? stream.src
        let sourceURL = URL(string: pageString) ?? URL(string: stream.src) ?? URL(string: "about:blank")!
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
