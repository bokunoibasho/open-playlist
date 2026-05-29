import SwiftUI

struct ContentView: View {
    @State private var controller = PlaybackController()
    @State private var pip = PictureInPictureController()
    @State private var showingPlayer = false

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("ライブラリ", systemImage: "music.note.list") }
            BrowserView()
                .tabItem { Label("ブラウザ", systemImage: "globe") }
        }
        .environment(controller)
        .environment(pip)
        .safeAreaInset(edge: .bottom) {
            if controller.currentTrack != nil {
                MiniPlayerView { showingPlayer = true }
                    .environment(controller)
            }
        }
        .sheet(isPresented: $showingPlayer) {
            PlayerView()
                .environment(controller)
                .environment(pip)
        }
        .onAppear {
            pip.setPlayer(controller.avPlayer)
            // PiP's "return to app" control re-opens the Now Playing sheet.
            pip.restoreUI = { showingPlayer = true }
        }
    }
}

#Preview {
    ContentView()
}
