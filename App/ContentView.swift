import SwiftUI

struct ContentView: View {
    @State private var controller = PlaybackController()
    @State private var showingPlayer = false

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("ライブラリ", systemImage: "music.note.list") }
            BrowserView()
                .tabItem { Label("ブラウザ", systemImage: "globe") }
        }
        .environment(controller)
        .safeAreaInset(edge: .bottom) {
            if controller.currentTrack != nil {
                MiniPlayerView { showingPlayer = true }
                    .environment(controller)
            }
        }
        .sheet(isPresented: $showingPlayer) {
            PlayerView()
                .environment(controller)
        }
    }
}

#Preview {
    ContentView()
}
