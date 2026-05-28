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
    var thumbnailURL: URL?
    var localFileURL: URL?
    var dateAdded: Date
    /// Position within its playlist. SwiftData to-many relationships don't
    /// guarantee array order, so ordering is driven by this explicit field.
    var position: Int
    var playlist: Playlist?

    init(
        sourceURL: URL,
        providerID: String? = nil,
        title: String,
        author: String? = nil,
        durationSeconds: Double? = nil,
        thumbnailURL: URL? = nil,
        localFileURL: URL? = nil,
        dateAdded: Date = .now,
        position: Int = 0
    ) {
        self.sourceURL = sourceURL
        self.providerID = providerID
        self.title = title
        self.author = author
        self.durationSeconds = durationSeconds
        self.thumbnailURL = thumbnailURL
        self.localFileURL = localFileURL
        self.dateAdded = dateAdded
        self.position = position
    }
}
