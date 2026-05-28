import SwiftData
import SwiftUI

struct PlaylistDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var playlist: Playlist

    var body: some View {
        List {
            ForEach(playlist.orderedTracks) { track in
                TrackRow(track: track)
            }
            .onMove(perform: move)
            .onDelete(perform: delete)
        }
        .overlay {
            if playlist.tracks.isEmpty {
                ContentUnavailableView(
                    "曲がありません",
                    systemImage: "music.note",
                    description: Text("ブラウザで動画を再生し「追加」でここに保存します")
                )
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        PlaylistStore(context: context).move(in: playlist, from: source, to: destination)
    }

    private func delete(at offsets: IndexSet) {
        let store = PlaylistStore(context: context)
        let ordered = playlist.orderedTracks
        for index in offsets { store.delete(ordered[index]) }
    }
}

private struct TrackRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: track.thumbnailURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(2)
                if let duration = track.durationSeconds, duration > 0 {
                    Text(formatted(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formatted(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
