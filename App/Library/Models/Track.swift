import Foundation
import SwiftData

/// A saved item in a playlist (DESIGN.md §5). The stream URL is never stored —
/// it is short-lived and re-resolved at playback time (Phase 5) from
/// `sourceURL` / `providerID`. `localFileURL` is set only once downloaded (Phase 7).
@Model
final class Track {
    var sourceURL: URL
    var providerID: String?
    var title: String
    var author: String?
    var durationSeconds: Double?
    /// Filename (relative to `DownloadLocations.directory`) of the offline copy,
    /// set once downloaded (Phase 7). We persist only the name, not an absolute
    /// path: the sandbox container path is not stable across launches/updates.
    var downloadFileName: String?
    var dateAdded: Date
    /// Position within its playlist. SwiftData to-many relationships don't
    /// guarantee array order, so ordering is driven by this explicit field.
    var position: Int
    var playlist: Playlist?

    /// Absolute URL of the downloaded file, rebuilt from `downloadFileName`.
    /// Computed (transient) — playback prefers this over re-resolving the stream
    /// (DESIGN.md §6.3). Callers must still confirm the file exists on disk.
    var localFileURL: URL? {
        downloadFileName.map { DownloadLocations.directory.appendingPathComponent($0) }
    }

    /// Cover image URL, derived from the YouTube video ID. We use the 16:9
    /// `mqdefault` variant (320×180) rather than `hqdefault` (4:3) so square
    /// cells crop cleanly instead of showing YouTube's baked-in letterbox bars
    /// (#46). Non-YouTube tracks (no providerID) have no thumbnail, as before.
    var thumbnailURL: URL? {
        providerID.flatMap {
            URL(string: "https://img.youtube.com/vi/\($0)/mqdefault.jpg")
        }
    }

    /// High-resolution cover (1280×720) for the few large surfaces — the
    /// full-screen audio art and the lock screen. Exists only for HD uploads, so
    /// callers must fall back to `thumbnailURL` when this 404s (#48). Loaded via
    /// `ArtworkLoader`, which performs that fallback.
    var highResThumbnailURL: URL? {
        providerID.flatMap {
            URL(string: "https://img.youtube.com/vi/\($0)/maxresdefault.jpg")
        }
    }

    init(
        sourceURL: URL,
        providerID: String? = nil,
        title: String,
        author: String? = nil,
        durationSeconds: Double? = nil,
        downloadFileName: String? = nil,
        dateAdded: Date = .now,
        position: Int = 0
    ) {
        self.sourceURL = sourceURL
        self.providerID = providerID
        self.title = title
        self.author = author
        self.durationSeconds = durationSeconds
        self.downloadFileName = downloadFileName
        self.dateAdded = dateAdded
        self.position = position
    }
}
