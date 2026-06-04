import MediaPlayer
import UIKit

/// Bridges playback state to the system (DESIGN.md §6.4): the lock-screen /
/// Control Center Now Playing info (`MPNowPlayingInfoCenter`) and the remote
/// transport commands (`MPRemoteCommandCenter`).
@MainActor
final class NowPlayingService {
    /// Remote transport callbacks, supplied by `PlaybackController`. `@MainActor`
    /// so the struct is Sendable and the commands can hop onto the main actor.
    struct Handlers: Sendable {
        let play: @MainActor () -> Void
        let pause: @MainActor () -> Void
        let toggle: @MainActor () -> Void
        let next: @MainActor () -> Void
        let previous: @MainActor () -> Void
        let seek: @MainActor (Double) -> Void
    }

    private var artworkTask: Task<Void, Never>?
    private var artworkURL: URL?

    // MARK: - Now Playing info

    func update(track: Track, isPlaying: Bool, elapsed: Double, duration: Double?, rate: Float) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = track.author
        info[MPMediaItemPropertyMediaType] = MPMediaType.anyAudio.rawValue
        if let duration, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        // Report the real speed so the lock-screen / Control Center clock advances
        // at the playback rate, not always 1× (#31).
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(rate)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtwork(highRes: track.highResThumbnailURL, fallback: track.thumbnailURL)
    }

    func clear() {
        artworkTask?.cancel()
        artworkURL = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func loadArtwork(highRes: URL?, fallback: URL?) {
        // Key dedup / race-guarding on the stable `mqdefault` URL: it's one per
        // track regardless of whether the HD variant exists.
        let key = fallback ?? highRes
        guard let key, key != artworkURL else { return }
        artworkURL = key
        artworkTask?.cancel()
        // Must be @MainActor: the continuation after the network await ends up
        // setting MPNowPlayingInfoCenter, which asserts it runs on the main
        // queue. Relying on inherited isolation let the resume land off-main and
        // crash (Issue #21). Explicit @MainActor forces the hop back to main.
        artworkTask = Task { @MainActor [weak self] in
            guard let image = await ArtworkLoader.load(highRes: highRes, fallback: fallback),
                  !Task.isCancelled
            else { return }
            self?.applyArtwork(image, for: key)
        }
    }

    private func applyArtwork(_ image: UIImage, for url: URL) {
        guard url == artworkURL else { return }  // a newer track won the race
        let art = squareCropped(image)
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        // The request handler must be @Sendable: MediaPlayer invokes it on its
        // own (non-main) accessQueue. Without @Sendable the closure inherits this
        // type's @MainActor isolation, so the runtime's executor check trips
        // dispatch_assert_queue(main) and crashes (Issue #21).
        info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { @Sendable _ in art }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Center-crops to a square (short-side²). Now Playing shows art in a square
    /// slot, so handing it our 16:9 `mqdefault` makes the system letterbox it —
    /// 1:1 art-track covers then keep the dark pillarbox bars baked into the
    /// 16:9 frame. Cropping to the centered square drops those bars and presents
    /// just the cover, matching the full-screen player's 1:1 art (#49).
    private func squareCropped(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage, cg.width != cg.height else { return image }
        let side = min(cg.width, cg.height)
        let rect = CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2,
                          width: side, height: side)
        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Remote commands

    func configureCommands(_ handlers: Handlers) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { @Sendable _ in
            Task { @MainActor in handlers.play() }
            return .success
        }
        center.pauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in handlers.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in handlers.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { @Sendable _ in
            Task { @MainActor in handlers.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { @Sendable _ in
            Task { @MainActor in handlers.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { @Sendable event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = event.positionTime
            Task { @MainActor in handlers.seek(position) }
            return .success
        }
    }
}
