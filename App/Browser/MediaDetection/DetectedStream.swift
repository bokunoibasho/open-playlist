import Foundation

/// A media stream detected in a web page by the injected Playlist UserScript.
/// Mirrors the payload posted by `PlaylistScript.js` (Brave-踏襲). Stream URLs
/// are short-lived, so this is transient detection data — not persisted as-is
/// (see DESIGN.md §5).
struct DetectedStream: Codable, Identifiable, Equatable {
    let name: String?
    let src: String
    let pageSrc: String?
    let pageTitle: String?
    let mimeType: String?
    let duration: Double?
    let detected: Bool?
    let tagId: String?
    let invisible: Bool?

    var id: String { src }
}
