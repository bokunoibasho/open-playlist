import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Open Playlist")
                .font(.title.bold())
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
