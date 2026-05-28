import AVFoundation
import Observation
import OSLog

/// Drives playback for a playlist (DESIGN.md §6.3). Uses a single `AVPlayer`
/// with a queue we manage ourselves: because stream URLs are short-lived
/// (DESIGN.md §5) we never pre-resolve — each track's URL is re-resolved
/// just-in-time as it becomes current, then handed to the player.
@MainActor
@Observable
final class PlaybackController {
    private(set) var currentTrack: Track?
    private(set) var isPlaying = false
    /// True while the current track's stream URL is being re-resolved.
    private(set) var isResolving = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var errorMessage: String?

    @ObservationIgnored private var queue: [Track] = []
    @ObservationIgnored private var currentIndex = 0

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let resolver: any StreamResolver
    @ObservationIgnored private let nowPlaying: NowPlayingService

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var startTask: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.openplaylist.app", category: "Playback")

    init(
        resolver: any StreamResolver = UserScriptStreamResolver(),
        nowPlaying: NowPlayingService = NowPlayingService()
    ) {
        self.resolver = resolver
        self.nowPlaying = nowPlaying
        player.allowsExternalPlayback = false
        addPeriodicTimeObserver()
        configureRemoteCommands()
    }

    var hasNext: Bool { currentIndex + 1 < queue.count }
    var hasPrevious: Bool { currentIndex > 0 }

    // MARK: - Transport

    func play(_ tracks: [Track], startAt index: Int) {
        guard tracks.indices.contains(index) else { return }
        queue = tracks
        currentIndex = index
        startCurrent()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard currentTrack != nil else { return }
        AudioSessionService.activate()
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func next() {
        guard hasNext else { return }
        currentIndex += 1
        startCurrent()
    }

    /// Music-app behaviour: restart the current track unless we're near its
    /// start, in which case step back to the previous one.
    func previous() {
        if currentTime > 3 || !hasPrevious {
            seek(to: 0)
            return
        }
        currentIndex -= 1
        startCurrent()
    }

    func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
        updateNowPlaying()
    }

    // MARK: - Current track

    private func startCurrent() {
        guard queue.indices.contains(currentIndex) else { return }
        let track = queue[currentIndex]
        currentTrack = track
        currentTime = 0
        duration = track.durationSeconds ?? 0
        errorMessage = nil
        isPlaying = false

        startTask?.cancel()
        startTask = Task { [weak self] in
            guard let self else { return }
            self.isResolving = true
            defer { self.isResolving = false }
            do {
                let url = try await self.resolver.resolve(track)
                // Bail if another track was selected while we were resolving.
                guard !Task.isCancelled, self.currentTrack === track else { return }
                self.beginPlayback(url: url)
            } catch is CancellationError {
                // Superseded by a newer selection; nothing to report.
            } catch {
                guard self.currentTrack === track else { return }
                Self.logger.error("Resolve failed: \(error.localizedDescription, privacy: .public)")
                self.errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    private func beginPlayback(url: URL) {
        let item = AVPlayerItem(url: url)
        observeEnd(of: item)
        observeStatus(of: item)
        player.replaceCurrentItem(with: item)
        AudioSessionService.activate()
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    // MARK: - Observers

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
            }
        }
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleEnd() }
        }
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.errorMessage = message ?? "再生に失敗しました"
                self?.isPlaying = false
            }
        }
    }

    private func handleEnd() {
        if hasNext {
            next()
        } else {
            isPlaying = false
            updateNowPlaying()
        }
    }

    // MARK: - Now Playing

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            nowPlaying.clear()
            return
        }
        let elapsed = player.currentTime().seconds
        nowPlaying.update(
            track: track,
            isPlaying: isPlaying,
            elapsed: elapsed.isFinite ? elapsed : 0,
            duration: duration > 0 ? duration : track.durationSeconds
        )
    }

    private func configureRemoteCommands() {
        nowPlaying.configureCommands(.init(
            play: { [weak self] in self?.resume() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() },
            seek: { [weak self] seconds in self?.seek(to: seconds) }
        ))
    }
}
