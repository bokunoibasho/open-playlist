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

    func update(track: Track, isPlaying: Bool, elapsed: Double, duration: Double?) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = track.author
        info[MPMediaItemPropertyMediaType] = MPMediaType.anyAudio.rawValue
        if let duration, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtwork(from: track.thumbnailURL)
    }

    func clear() {
        artworkTask?.cancel()
        artworkURL = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func loadArtwork(from url: URL?) {
        guard let url else { return }
        guard url != artworkURL else { return }
        artworkURL = url
        artworkTask?.cancel()
        // Must be @MainActor: the continuation after the network await ends up
        // setting MPNowPlayingInfoCenter, which asserts it runs on the main
        // queue. Relying on inherited isolation let the resume land off-main and
        // crash (Issue #21). Explicit @MainActor forces the hop back to main.
        artworkTask = Task { @MainActor [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  !Task.isCancelled
            else { return }
            self?.applyArtwork(image, for: url)
        }
    }

    private func applyArtwork(_ image: UIImage, for url: URL) {
        guard url == artworkURL else { return }  // a newer track won the race
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        // The request handler must be @Sendable: MediaPlayer invokes it on its
        // own (non-main) accessQueue. Without @Sendable the closure inherits this
        // type's @MainActor isolation, so the runtime's executor check trips
        // dispatch_assert_queue(main) and crashes (Issue #21).
        info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
