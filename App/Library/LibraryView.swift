import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Playlist.dateCreated) private var playlists: [Playlist]

    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        HStack(spacing: 12) {
                            PlaylistArtwork(playlist: playlist, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                    .font(.headline)
                                Text("\(playlist.tracks.count) 曲")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if playlists.isEmpty {
                    ContentUnavailableView(
                        "プレイリストなし",
                        systemImage: "music.note.list",
                        description: Text("＋ で作成、ブラウザで見つけた曲を追加できます")
                    )
                }
            }
            .navigationTitle("ライブラリ")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newPlaylistName = ""
                        showingNewPlaylist = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("新規プレイリスト", isPresented: $showingNewPlaylist) {
                TextField("名前", text: $newPlaylistName)
                Button("作成") { createPlaylist() }
                Button("キャンセル", role: .cancel) {}
            }
        }
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        PlaylistStore(context: context).createPlaylist(name: name.isEmpty ? "新しいプレイリスト" : name)
    }

    private func delete(at offsets: IndexSet) {
        let store = PlaylistStore(context: context)
        for index in offsets { store.delete(playlists[index]) }
    }
}
