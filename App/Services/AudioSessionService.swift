import AVFoundation

enum AudioSessionService {
    // Category is set at launch so background audio is wired up;
    // activate() is called when playback actually starts.
    static func configurePlayback() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            assertionFailure("Failed to configure AVAudioSession: \(error)")
        }
    }

    /// Make this app the active audio session — required for background /
    /// lock-screen playback. Called when playback starts.
    static func activate() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            assertionFailure("Failed to activate AVAudioSession: \(error)")
        }
    }

    static func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            assertionFailure("Failed to deactivate AVAudioSession: \(error)")
        }
    }
}
