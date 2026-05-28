import SwiftUI

/// Persistent bar shown above the tab bar while something is loaded. Tapping the
/// body expands the full-screen `PlayerView`; the buttons act in place.
struct MiniPlayerView: View {
    @Environment(PlaybackController.self) private var controller
    let onExpand: () -> Void

    var body: some View {
        if let track = controller.currentTrack {
            HStack(spacing: 12) {
                artwork(for: track)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    if controller.isResolving {
                        Text("読み込み中…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let author = track.author, !author.isEmpty {
                        Text(author)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    controller.togglePlayPause()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .disabled(controller.isResolving)

                Button {
                    controller.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .disabled(!controller.hasNext)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)
        }
    }

    @ViewBuilder
    private func artwork(for track: Track) -> some View {
        AsyncImage(url: track.thumbnailURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Image(systemName: "music.note").foregroundStyle(.secondary)
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}
