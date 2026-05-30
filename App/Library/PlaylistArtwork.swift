import SwiftUI

/// Playlist cover art (Phase 8): the first track's thumbnail, a 2×2 collage of
/// the first four when available, or a music-note placeholder. Reused by the
/// library list rows and the playlist-detail header.
struct PlaylistArtwork: View {
    let playlist: Playlist
    var size: CGFloat
    var cornerRadius: CGFloat = 8

    private var thumbnails: [URL] {
        playlist.orderedTracks.compactMap(\.thumbnailURL)
    }

    var body: some View {
        let thumbs = thumbnails
        Group {
            if thumbs.count >= 4 {
                collage(Array(thumbs.prefix(4)))
            } else if let first = thumbs.first {
                tile(first)
            } else {
                Image(systemName: "music.note.list")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private func tile(_ url: URL) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.clear
        }
    }

    private func collage(_ urls: [URL]) -> some View {
        let half = size / 2
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                tile(urls[0]).frame(width: half, height: half).clipped()
                tile(urls[1]).frame(width: half, height: half).clipped()
            }
            HStack(spacing: 0) {
                tile(urls[2]).frame(width: half, height: half).clipped()
                tile(urls[3]).frame(width: half, height: half).clipped()
            }
        }
    }
}
