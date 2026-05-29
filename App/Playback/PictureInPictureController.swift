import AVKit
import Observation
import OSLog
import SwiftUI

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
    /// The player bound via `setPlayer`. Kept so we can re-attach it to the layer
    /// after detaching for background audio (see `handleScenePhase`).
    @ObservationIgnored private var boundPlayer: AVPlayer?

    private static let logger = Logger(subsystem: "com.openplaylist.app", category: "PiP")

    /// Bind the player whose video should be PiP-able. Called once: the
    /// `PlaybackController` keeps a single `AVPlayer` for its lifetime.
    func setPlayer(_ player: AVPlayer) {
        boundPlayer = player
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
            @Sendable [weak self] controller, _ in
            // @Sendable so this KVO callback isn't main-actor-isolated (the
            // runtime would otherwise assert main-queue when it's delivered
            // off-main — Issue #21). Read the Sendable Bool here, then hop.
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor [weak self] in
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

    /// Keep audio playing when backgrounded (Issue #23). Downloaded tracks are
    /// video-bearing mp4s; an `AVPlayerLayer` that stays attached to the player
    /// but has no visible surface to render into (the Now Playing sheet is
    /// usually dismissed) makes the player pause on background. Detaching the
    /// player from the layer lets audio continue. PiP is the exception: while it
    /// owns the video, background rendering is allowed, so we keep the layer
    /// attached.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if playerLayer.player == nil { playerLayer.player = boundPlayer }
        case .background:
            if !(pipController?.isPictureInPictureActive ?? false) {
                playerLayer.player = nil
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}

extension PictureInPictureController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in isActive = false }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            Self.logger.error("PiP failed to start: \(error.localizedDescription, privacy: .public)")
            isActive = false
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in restoreUI?() }
        completionHandler(true)
    }
}
