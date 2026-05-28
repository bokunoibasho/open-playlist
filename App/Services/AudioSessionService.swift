import AVFoundation

enum AudioSessionService {
    // Category is set at launch so background audio is wired up;
    // setActive(true) is called when playback actually starts (Phase 5).
    static func configurePlayback() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            assertionFailure("Failed to configure AVAudioSession: \(error)")
        }
    }
}
