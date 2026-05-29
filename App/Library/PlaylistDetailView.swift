import SwiftData
import SwiftUI

struct PlaylistDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlaybackController.self) private var controller
    @Environment(DownloadManager.self) private var downloads
    @Bindable var playlist: Playlist

    var body: some View {
        List {
            ForEach(Array(playlist.orderedTracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    playOrDownload(track, at: index)
                } label: {
                    TrackRow(track: track, isCurrent: controller.currentTrack === track)
                }
                .buttonStyle(.plain)
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

    private func playOrDownload(_ track: Track, at index: Int) {
        if downloads.isDownloaded(track) {
            controller.play(playlist.orderedTracks, startAt: index)
        } else {
            downloads.download(track)
        }
    }
}

private struct TrackRow: View {
    @Environment(DownloadManager.self) private var downloads
    let track: Track
    var isCurrent = false

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
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                if let duration = track.durationSeconds, duration > 0 {
                    Text(formatted(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            downloadIndicator

            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .contextMenu { downloadMenu }
    }

    @ViewBuilder
    private var downloadIndicator: some View {
        let state = downloads.state(for: track)
        if case .downloading(let fraction)? = state {
            ProgressView(value: fraction)
                .progressViewStyle(.circular)
                .controlSize(.small)
        } else if case .failed? = state {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if downloads.isDownloaded(track) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var downloadMenu: some View {
        if case .downloading? = downloads.state(for: track) {
            Button {
                downloads.cancel(track)
            } label: {
                Label("ダウンロードをキャンセル", systemImage: "xmark.circle")
            }
        } else if track.downloadFileName != nil {
            Button(role: .destructive) {
                downloads.removeDownload(track)
            } label: {
                Label("ダウンロードを削除", systemImage: "trash")
            }
        } else {
            Button {
                downloads.download(track)
            } label: {
                Label("ダウンロード", systemImage: "arrow.down.circle")
            }
        }
    }

    private func formatted(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
