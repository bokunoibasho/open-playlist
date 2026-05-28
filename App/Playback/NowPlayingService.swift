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
        artworkTask = Task { [weak self] in
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
        info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote commands

    func configureCommands(_ handlers: Handlers) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in
            MainActor.assumeIsolated { handlers.play() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            MainActor.assumeIsolated { handlers.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            MainActor.assumeIsolated { handlers.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            MainActor.assumeIsolated { handlers.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            MainActor.assumeIsolated { handlers.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            MainActor.assumeIsolated { handlers.seek(event.positionTime) }
            return .success
        }
    }
}
