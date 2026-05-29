import AVFoundation

/// Shared playability check for downloaded-only playback. A file is usable only
/// when AVFoundation reports it playable *and* it carries at least one audio or
/// video track. Used by both the downloader (validate before keeping the file)
/// and the player (validate before handing it to AVPlayer).
enum MediaValidation {
    static func hasPlayableMedia(at url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isPlayable)) == true else { return false }
        let audio = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let video = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        return !audio.isEmpty || !video.isEmpty
    }
}
