import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Playlist.dateCreated) private var playlists: [Playlist]

    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""

    @State private var renameTarget: Playlist?
    @State private var renameName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(playlists) { playlist in
                    NavigationLink(value: playlist) {
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
                    .contextMenu {
                        Button {
                            startRename(playlist)
                        } label: {
                            Label("名前を変更", systemImage: "pencil")
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            // Value-based navigation keeps the pushed detail bound to the stack's
            // path rather than to the row's NavigationLink view. A legacy
            // `NavigationLink { destination }` inside a @Query-driven List pops
            // itself when the List is diffed/rebuilt — e.g. the first time
            // playback mutates observed state — which surfaced as the detail
            // view popping back to the library on the first shuffle after launch
            // (#60).
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
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
            .alert("名前を変更", isPresented: isRenaming) {
                TextField("名前", text: $renameName)
                Button("保存") { commitRename() }
                Button("キャンセル", role: .cancel) {}
            }
        }
    }

    /// True while a rename alert is up; clearing it drops the target so the
    /// alert dismisses (the Bool the alert needs, derived from the optional).
    private var isRenaming: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        PlaylistStore(context: context).createPlaylist(name: name.isEmpty ? "新しいプレイリスト" : name)
    }

    private func startRename(_ playlist: Playlist) {
        renameName = playlist.name
        renameTarget = playlist
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        PlaylistStore(context: context).rename(target, to: renameName)
        renameTarget = nil
    }

    private func delete(at offsets: IndexSet) {
        let store = PlaylistStore(context: context)
        for index in offsets { store.delete(playlists[index]) }
    }
}
