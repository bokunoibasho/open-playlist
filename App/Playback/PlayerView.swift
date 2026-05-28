import SwiftUI

/// Full-screen Now Playing surface (presented as a sheet). Functional rather
/// than polished — visual finish lands in Phase 8.
struct PlayerView: View {
    @Environment(PlaybackController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    @State private var isScrubbing = false
    @State private var scrubValue = 0.0

    var body: some View {
        VStack(spacing: 24) {
            if let track = controller.currentTrack {
                artwork(for: track)

                VStack(spacing: 4) {
                    Text(track.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let author = track.author, !author.isEmpty {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                scrubber

                transportControls

                if let error = controller.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            } else {
                ContentUnavailableView("再生中の曲がありません", systemImage: "music.note")
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .center)
        .presentationDragIndicator(.visible)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .padding()
            }
            .tint(.secondary)
        }
    }

    @ViewBuilder
    private func artwork(for track: Track) -> some View {
        AsyncImage(url: track.thumbnailURL) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } placeholder: {
            Image(systemName: "music.note")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if controller.isResolving {
                ProgressView()
                    .controlSize(.large)
                    .padding()
                    .background(.thinMaterial, in: Circle())
            }
        }
    }

    private var scrubber: some View {
        let total = max(controller.duration, 0.1)
        return VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubValue : min(controller.currentTime, total) },
                    set: { scrubValue = $0 }
                ),
                in: 0...total,
                onEditingChanged: { editing in
                    if editing {
                        isScrubbing = true
                        scrubValue = controller.currentTime
                    } else {
                        controller.seek(to: scrubValue)
                        isScrubbing = false
                    }
                }
            )
            HStack {
                Text(timecode(isScrubbing ? scrubValue : controller.currentTime))
                Spacer()
                Text(timecode(controller.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 48) {
            Button { controller.previous() } label: {
                Image(systemName: "backward.fill").font(.title)
            }
            Button { controller.togglePlayPause() } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 48))
            }
            .disabled(controller.isResolving)
            Button { controller.next() } label: {
                Image(systemName: "forward.fill").font(.title)
            }
            .disabled(!controller.hasNext)
        }
        .tint(.primary)
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
