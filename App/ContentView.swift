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
        // Keep the bottom-accessory modifier *always applied* and toggle only the
        // capsule's visibility. The earlier version added/removed the modifier
        // itself (`if isPresented { content.tabViewBottomAccessory } else
        // { content }`), which re-identifies the whole TabView the first time a
        // track starts (currentTrack nil → non-nil): that tears down each tab's
        // NavigationStack — popping the playlist detail back to the library — and
        // the Browser tab's WKWebView. That was #60, reproducing only on the first
        // play after launch (the one moment the accessory appeared). See
        // MiniPlayerAccessory.
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

/// Hosts the iOS 26 tab-view bottom accessory (mini-player). The modifier is
/// applied unconditionally so the TabView keeps a stable identity — toggling the
/// accessory on/off re-identifies the tab subtree, popping the pushed playlist
/// detail and tearing down the Browser tab's WKWebView (#60). Visibility is
/// driven by `isPresented`:
/// - iOS 26.1+: the `isEnabled:` overload hides the glass capsule cleanly while
///   nothing is playing.
/// - iOS 26.0: that overload doesn't exist, so the capsule stays applied (still
///   no pop); the only cost is an empty capsule while nothing plays.
private struct MiniPlayerAccessory<Accessory: View>: ViewModifier {
    let isPresented: Bool
    @ViewBuilder var accessory: () -> Accessory

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isPresented) { accessory() }
        } else {
            content.tabViewBottomAccessory { accessory() }
        }
    }
}

#Preview {
    ContentView()
}
