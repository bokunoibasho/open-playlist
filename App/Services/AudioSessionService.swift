import AVFoundation
import OSLog

enum AudioSessionService {
    private static let logger = Logger(subsystem: "com.openplaylist.app", category: "AudioSession")

    // Category is set at launch so background audio is wired up;
    // activate() is called when playback actually starts.
    static func configurePlayback() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            logger.error("Failed to configure AVAudioSession: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Make this app the active audio session — required for background /
    /// lock-screen playback. Called when playback starts.
    static func activate() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error("Failed to activate AVAudioSession: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Failed to deactivate AVAudioSession: \(error.localizedDescription, privacy: .public)")
        }
    }
}
