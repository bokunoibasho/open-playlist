import SwiftUI

struct ContentView: View {
    @State private var controller = PlaybackController()
    @State private var pip = PictureInPictureController()
    @State private var downloads = DownloadManager()
    @State private var showingPlayer = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // iOS 26 `Tab` + `.tabViewBottomAccessory` so the mini-player rides above
        // the Liquid Glass tab bar (Apple Music style) instead of covering it —
        // `.safeAreaInset` covered the whole bar, blocking the Browser tab (#22).
        TabView {
            Tab("ライブラリ", systemImage: "music.note.list") {
                LibraryView()
            }
            Tab("ブラウザ", systemImage: "globe") {
                BrowserView()
            }
        }
        .environment(controller)
        .environment(pip)
        .environment(downloads)
        // Apply the accessory only while something is loaded, otherwise an empty
        // glass capsule floats above the tab bar. Done via a ViewModifier on the
        // stable `Content` placeholder (not an inline if/else around the TabView)
        // so toggling it doesn't re-identify the tab subtree and tear down the
        // browser's WKWebView (held in BrowserView's @State).
        .modifier(
            MiniPlayerAccessory(isPresented: controller.currentTrack != nil) {
                MiniPlayerView { showingPlayer = true }
                    .environment(controller)
            }
        )
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
        // Keep background/lock-screen audio alive by detaching the video layer
        // when backgrounded and re-attaching on return (#23).
        .onChange(of: scenePhase) { _, phase in
            pip.handleScenePhase(phase)
        }
    }
}

/// Adds the iOS 26 tab-view bottom accessory only when `isPresented`, so the
/// glass capsule disappears entirely when nothing is playing. Conditioning the
/// `Content` placeholder (rather than the TabView itself) keeps tab/web-view
/// identity stable across the toggle.
private struct MiniPlayerAccessory<Accessory: View>: ViewModifier {
    let isPresented: Bool
    @ViewBuilder var accessory: () -> Accessory

    func body(content: Content) -> some View {
        if isPresented {
            content.tabViewBottomAccessory { accessory() }
        } else {
            content
        }
    }
}

#Preview {
    ContentView()
}
