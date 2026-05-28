import Foundation
import SwiftData

/// An ordered collection of tracks (DESIGN.md §5). Deleting a playlist cascades
/// to its tracks. Display order comes from `Track.position`, not relationship
/// array order — use `orderedTracks`.
@Model
final class Playlist {
    var name: String
    var dateCreated: Date

    @Relationship(deleteRule: .cascade, inverse: \Track.playlist)
    var tracks: [Track]

    init(name: String, dateCreated: Date = .now) {
        self.name = name
        self.dateCreated = dateCreated
        self.tracks = []
    }

    var orderedTracks: [Track] {
        tracks.sorted { $0.position < $1.position }
    }
}
