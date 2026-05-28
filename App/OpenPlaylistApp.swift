import SwiftUI

@main
struct OpenPlaylistApp: App {
    init() {
        AudioSessionService.configurePlayback()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
