import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("ライブラリ", systemImage: "music.note.list") }
            BrowserView()
                .tabItem { Label("ブラウザ", systemImage: "globe") }
        }
    }
}

#Preview {
    ContentView()
}
