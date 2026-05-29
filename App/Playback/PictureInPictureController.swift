import AVKit
import Observation
import OSLog

/// Owns the Picture in Picture lifecycle (DESIGN.md §6.5). PiP needs an
/// `AVPlayerLayer` living in the view hierarchy, but it must keep working after
/// the Now Playing sheet (which hosts that layer) is dismissed — so this
/// controller *owns* the layer strongly and views merely display it as a
/// sublayer. The layer therefore outlives any host view.
@MainActor
@Observable
final class PictureInPictureController: NSObject {
    /// The layer views render. Owned here so PiP survives host-view teardown.
    @ObservationIgnored let playerLayer = AVPlayerLayer()

    /// False on simulators and unsupported devices — drives whether the UI
    /// offers a PiP control at all.
    let isSupported = AVPictureInPictureController.isPictureInPictureSupported()

    /// True only when there is playable video to pop out (audio-only items
    /// never become possible).
    private(set) var isPossible = false
    private(set) var isActive = false

    /// Invoked when the user taps PiP's "return to app" control; the app should
    /// re-present the Now Playing surface.
    var restoreUI: (() -> Void)?

    @ObservationIgnored private var pipController: AVPictureInPictureController?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?

    private static let logger = Logger(subsystem: "com.openplaylist.app", category: "PiP")

    /// Bind the player whose video should be PiP-able. Called once: the
    /// `PlaybackController` keeps a single `AVPlayer` for its lifetime.
    func setPlayer(_ player: AVPlayer) {
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect

        guard isSupported, pipController == nil else { return }
        guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
            Self.logger.error("Failed to create AVPictureInPictureController")
            return
        }
        controller.delegate = self
        // Auto-enter PiP when the app is backgrounded during video playback.
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pipController = controller

        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
            [weak self] controller, _ in
            // KVO for AVPictureInPictureController is delivered on the main
            // thread; read the (Sendable) Bool before hopping so the
            // non-Sendable controller never crosses the isolation boundary.
            let possible = controller.isPictureInPicturePossible
            MainActor.assumeIsolated {
                self?.isPossible = possible
            }
        }
    }

    func toggle() {
        guard let pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else if pipController.isPictureInPicturePossible {
            pipController.startPictureInPicture()
        }
    }
}

extension PictureInPictureController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        MainActor.assumeIsolated { isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        MainActor.assumeIsolated { isActive = false }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        MainActor.assumeIsolated {
            Self.logger.error("PiP failed to start: \(error.localizedDescription, privacy: .public)")
            isActive = false
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        MainActor.assumeIsolated { restoreUI?() }
        completionHandler(true)
    }
}
