import AVFoundation
import Observation

/// Drives local playback for a playlist (DESIGN.md §6.3). Uses a single
/// `AVPlayer` with a queue we manage ourselves. Library playback is intentionally
/// limited to downloaded files; live stream re-resolution is used only by the
/// downloader.
@MainActor
@Observable
final class PlaybackController {
    private(set) var currentTrack: Track?
    private(set) var isPlaying = false
    /// Kept for the player UI; library playback itself no longer re-resolves
    /// streams.
    private(set) var isResolving = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var errorMessage: String?
    /// True once the current item is known to carry a video track — drives
    /// whether the UI shows live video (and PiP) vs. just the thumbnail.
    private(set) var hasVideo = false
    /// Repeat mode for the queue (Phase 8): `.one` restarts the current track,
    /// `.all` wraps past the end, `.off` stops at the end.
    private(set) var repeatMode: RepeatMode = .off
    /// Whether the queue is currently shuffled (Phase 8).
    private(set) var isShuffled = false

    enum RepeatMode: CaseIterable {
        case off, all, one
    }

    @ObservationIgnored private var queue: [Track] = []
    @ObservationIgnored private var currentIndex = 0
    /// The unshuffled source order, so shuffle can be toggled off and restored.
    @ObservationIgnored private var baseOrder: [Track] = []
    /// Set once the queue plays to its end with repeat off, so the next play
    /// press restarts from the top instead of no-op'ing on the ended item (#27).
    @ObservationIgnored private var didReachEnd = false

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let nowPlaying: NowPlayingService

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var startTask: Task<Void, Never>?

    init(nowPlaying: NowPlayingService = NowPlayingService()) {
        self.nowPlaying = nowPlaying
        player.allowsExternalPlayback = false
        addPeriodicTimeObserver()
        configureRemoteCommands()
    }

    var hasNext: Bool { currentIndex + 1 < queue.count }
    var hasPrevious: Bool { currentIndex > 0 }

    /// Read-only access to the underlying player, for video-layer rendering and
    /// PiP only. Transport still goes through this controller's methods.
    var avPlayer: AVPlayer { player }

    // MARK: - Transport

    func play(_ tracks: [Track], startAt index: Int, shuffled: Bool = false) {
        guard tracks.indices.contains(index) else { return }
        let target = tracks[index]
        // Downloaded-only playback (DESIGN.md §6.3): keep just the tracks with a
        // local file so transport (next/previous/auto-advance) never stalls on a
        // track we can't play. The tapped track is guaranteed downloaded by the
        // caller, so it survives the filter.
        let playable = tracks.filter(isPlayable)
        guard playable.contains(where: { $0 === target }) else { return }
        baseOrder = playable
        isShuffled = shuffled
        rebuildQueue(keeping: target)
        startCurrent()
    }

    /// Play a whole list — the playlist header's 再生 / シャッフル buttons (Phase 8).
    /// Shuffle randomizes the whole queue *including the first track*; in-order
    /// play starts at the top. Downloaded-only, so it no-ops on an all-unplayable
    /// list.
    func playAll(_ tracks: [Track], shuffled: Bool = false) {
        let playable = tracks.filter(isPlayable)
        guard !playable.isEmpty else { return }
        baseOrder = playable
        isShuffled = shuffled
        rebuildQueue(keeping: shuffled ? nil : playable[0])
        startCurrent()
    }

    func toggleShuffle() {
        guard let current = currentTrack else { return }
        isShuffled.toggle()
        rebuildQueue(keeping: current)
    }

    func cycleRepeatMode() {
        repeatMode = switch repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    /// Rebuilds `queue` from `baseOrder` for the current shuffle state. When
    /// `current` is given it stays the now-playing item (placed first if
    /// shuffled); when `nil` and shuffled, the whole queue is randomized — the
    /// first track included (used by the シャッフル button).
    private func rebuildQueue(keeping current: Track?) {
        if isShuffled {
            if let current {
                var rest = baseOrder.filter { $0 !== current }
                rest.shuffle()
                queue = [current] + rest
            } else {
                queue = baseOrder.shuffled()
            }
        } else {
            queue = baseOrder
        }
        currentIndex = current.flatMap { c in queue.firstIndex { $0 === c } } ?? 0
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
        // After the queue finished (repeat off), play restarts from the top of
        // the playlist rather than no-op'ing on the ended item (#27).
        if didReachEnd {
            currentIndex = 0
            startCurrent()
            return
        }
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
        didReachEnd = false
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
        updateNowPlaying()
    }

    // MARK: - Current track

    /// Playback is downloaded-only: a track is playable only when its download
    /// still exists on disk.
    private func isPlayable(_ track: Track) -> Bool {
        guard let url = track.localFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func startCurrent() {
        guard queue.indices.contains(currentIndex) else { return }
        let track = queue[currentIndex]
        currentTrack = track
        currentTime = 0
        duration = track.durationSeconds ?? 0
        errorMessage = nil
        didReachEnd = false
        isPlaying = false
        isResolving = false
        hasVideo = false
        player.pause()
        startTask?.cancel()

        // Downloaded tracks play straight from disk (DESIGN.md §6.3): no
        // re-resolution, so it works offline and skips the fragile re-resolve
        // path entirely (Issue #16/#21).
        if isPlayable(track), let local = track.localFileURL {
            // @MainActor so the continuation after `validatePlayableFile`
            // resumes on the main actor before touching the player / Now Playing
            // info (MPNowPlayingInfoCenter asserts main-queue). See Issue #21.
            startTask = Task { @MainActor [weak self] in
                guard let self else { return }
                self.isResolving = true
                defer { self.isResolving = false }
                do {
                    try await Self.validatePlayableFile(at: local)
                    guard !Task.isCancelled, self.currentTrack === track else { return }
                    self.beginPlayback(url: local)
                } catch is CancellationError {
                    // Superseded by a newer selection; nothing to report.
                } catch {
                    guard self.currentTrack === track else { return }
                    self.discardBrokenDownload(for: track, url: local)
                    self.errorMessage = "ダウンロードしたファイルを再生できませんでした。もう一度ダウンロードしてください"
                }
            }
            return
        }

        player.replaceCurrentItem(with: nil)
        errorMessage = "ダウンロード済みの曲だけ再生できます"
        nowPlaying.clear()
    }

    private static func validatePlayableFile(at url: URL) async throws {
        guard await MediaValidation.hasPlayableMedia(at: url) else {
            throw StreamResolverError.noPlayableStream
        }
    }

    private func discardBrokenDownload(for track: Track, url: URL) {
        player.replaceCurrentItem(with: nil)
        try? FileManager.default.removeItem(at: url)
        track.downloadFileName = nil
        try? track.modelContext?.save()
        nowPlaying.clear()
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
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
            Task { @MainActor [weak self] in self?.handleEnd() }
        }
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObservation?.invalidate()
        // @Sendable so this KVO callback — which AVFoundation may deliver off the
        // main thread — doesn't trip the main-actor executor check (Issue #21).
        // Read the Sendable bits here (the non-Sendable item must not cross the
        // hop); do the main-actor work after hopping.
        statusObservation = item.observe(\.status, options: [.new]) { @Sendable [weak self] item, _ in
            let status = item.status
            let failureMessage = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    await self.finishPreparing()
                case .failed:
                    self.errorMessage = failureMessage ?? "再生に失敗しました"
                    self.isPlaying = false
                default:
                    break
                }
            }
        }
    }

    /// Once the current item is ready, load secondary metadata asynchronously.
    /// Keep periodic playback ticks lightweight so the main thread stays responsive.
    private func finishPreparing() async {
        guard let item = player.currentItem else { return }
        if let itemDuration = try? await item.asset.load(.duration).seconds,
           itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }

        let tracks = try? await item.asset.loadTracks(withMediaType: .video)
        // Ignore if a newer item became current while we were loading.
        guard player.currentItem === item else { return }
        hasVideo = !(tracks?.isEmpty ?? true)
    }

    private func handleEnd() {
        switch repeatMode {
        case .one:
            seek(to: 0)
            player.play()
            isPlaying = true
            updateNowPlaying()
        case .all:
            if hasNext {
                next()
            } else if !queue.isEmpty {
                currentIndex = 0
                startCurrent()
            }
        case .off:
            if hasNext {
                next()
            } else {
                isPlaying = false
                didReachEnd = true
                updateNowPlaying()
            }
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
