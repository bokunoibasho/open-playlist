import SwiftData
import SwiftUI

/// Sheet for adding a detected stream to a playlist (new or existing).
struct AddToPlaylistView: View {
    let stream: DetectedStream
    /// The browser's current page URL — the authoritative watch-page source for
    /// the saved Track's `sourceURL` (Issue #16). Nil when unavailable.
    var pageURL: URL?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Playlist.dateCreated) private var playlists: [Playlist]

    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("新規プレイリスト") {
                    HStack {
                        TextField("名前", text: $newName)
                        Button("作成して追加") { addToNew() }
                            .buttonStyle(.borderless)
                    }
                }
                if !playlists.isEmpty {
                    Section("既存のプレイリスト") {
                        ForEach(playlists) { playlist in
                            Button {
                                add(to: playlist)
                            } label: {
                                HStack {
                                    Text(playlist.name)
                                    Spacer()
                                    Text("\(playlist.tracks.count)")
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("プレイリストに追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }

    private func addToNew() {
        let store = PlaylistStore(context: context)
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = store.createPlaylist(name: trimmed.isEmpty ? "新しいプレイリスト" : trimmed)
        store.add(stream, to: playlist, pageURL: pageURL)
        dismiss()
    }

    private func add(to playlist: Playlist) {
        PlaylistStore(context: context).add(stream, to: playlist, pageURL: pageURL)
        dismiss()
    }
}
