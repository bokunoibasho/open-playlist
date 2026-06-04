import SwiftUI

/// High-res cover art for the full-screen player's audio-only square. `AsyncImage`
/// can't fall back across URLs, so this loads `maxresdefault` via `ArtworkLoader`
/// and drops to `mqdefault` when the HD variant is missing (#48).
struct TrackArtworkView<Placeholder: View>: View {
    let track: Track
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        // Reset first so a track change (or a non-YouTube track) never lingers on
        // the previous cover while the new one loads.
        .task(id: track.thumbnailURL) {
            image = nil
            image = await ArtworkLoader.load(
                highRes: track.highResThumbnailURL,
                fallback: track.thumbnailURL
            )
        }
    }
}
