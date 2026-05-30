import SwiftUI

/// Full-screen Now Playing surface (presented as a sheet). Apple-Music-style
/// finish (Phase 8): blurred artwork backdrop, square artwork that breathes with
/// play/pause, a slim scrubber, and shuffle / repeat controls.
struct PlayerView: View {
    @Environment(PlaybackController.self) private var controller
    @Environment(PictureInPictureController.self) private var pip
    @Environment(\.dismiss) private var dismiss

    @State private var isScrubbing = false
    @State private var scrubValue = 0.0

    var body: some View {
        ZStack {
            if let track = controller.currentTrack {
                artworkBackground(for: track)

                VStack(spacing: 0) {
                    Spacer(minLength: 8)
                    artwork(for: track)
                    Spacer(minLength: 16)
                    trackInfo(for: track)
                        .padding(.bottom, 20)
                    scrubber
                        .padding(.bottom, 12)
                    transportControls
                    Spacer(minLength: 16)
                    bottomControls
                    if let error = controller.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            } else {
                ContentUnavailableView("再生中の曲がありません", systemImage: "music.note")
            }
        }
        .presentationDragIndicator(.visible)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .padding()
            }
            .tint(.secondary)
        }
    }

    // MARK: - Background

    /// Blurred, frosted artwork filling the sheet — the signature ambient look.
    /// A material overlay keeps it legible and adapts to light/dark.
    @ViewBuilder
    private func artworkBackground(for track: Track) -> some View {
        GeometryReader { geo in
            AsyncImage(url: track.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(.systemBackground)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(1.4)   // hide blur's translucent edges
            .blur(radius: 50)
            .overlay(Rectangle().fill(.ultraThinMaterial))
            .animation(.easeInOut(duration: 0.4), value: track.thumbnailURL)
        }
        .ignoresSafeArea()
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artwork(for track: Track) -> some View {
        if controller.hasVideo {
            // Real video stays 16:9 (Apple Music has no video, but we do).
            PlayerLayerView(pip: pip)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
                .overlay { resolvingOverlay }
        } else {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    AsyncImage(url: track.thumbnailURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "music.note")
                            .font(.system(size: 72))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
                .overlay { resolvingOverlay }
                // Breathe with playback, Apple-Music-style.
                .scaleEffect(controller.isPlaying ? 1.0 : 0.82)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: controller.isPlaying)
                .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private var resolvingOverlay: some View {
        if controller.isResolving {
            ProgressView()
                .controlSize(.large)
                .padding()
                .background(.thinMaterial, in: Circle())
        }
    }

    // MARK: - Track info

    private func trackInfo(for track: Track) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.title)
                .font(.title2.weight(.bold))
                .lineLimit(2)
            if let author = track.author, !author.isEmpty {
                Text(author)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        let total = max(controller.duration, 0.1)
        let elapsed = isScrubbing ? scrubValue : controller.currentTime
        return VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { min(elapsed, total) },
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
                Text(timecode(elapsed))
                Spacer()
                Text("-" + timecode(max(total - elapsed, 0)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Transport

    private var transportControls: some View {
        HStack(spacing: 56) {
            Button { controller.previous() } label: {
                Image(systemName: "backward.fill").font(.title)
            }
            Button { controller.togglePlayPause() } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 52))
                    .contentTransition(.symbolEffect(.replace))
            }
            .disabled(controller.isResolving)
            Button { controller.next() } label: {
                Image(systemName: "forward.fill").font(.title)
            }
            .disabled(!controller.hasNext)
        }
        .tint(.primary)
    }

    // MARK: - Bottom controls (shuffle / repeat / PiP)

    private var bottomControls: some View {
        HStack {
            Button { controller.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
            }
            .tint(controller.isShuffled ? .accentColor : .secondary)

            Spacer()

            speedMenu

            Spacer()

            if pip.isSupported {
                pipButton
                Spacer()
            }

            Button { controller.cycleRepeatMode() } label: {
                Image(systemName: repeatSymbol)
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .tint(controller.repeatMode == .off ? .secondary : .accentColor)
        }
        .padding(.horizontal, 8)
    }

    private var repeatSymbol: String {
        controller.repeatMode == .one ? "repeat.1" : "repeat"
    }

    // MARK: - Playback speed (#31)

    private var speedMenu: some View {
        Menu {
            Picker("再生速度", selection: speedBinding) {
                ForEach(PlaybackController.ratePresets, id: \.self) { rate in
                    Text(rateLabel(rate)).tag(rate)
                }
            }
        } label: {
            Text(rateLabel(controller.playbackRate))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .tint(controller.playbackRate == 1.0 ? .secondary : .accentColor)
    }

    private var speedBinding: Binding<Float> {
        Binding(
            get: { controller.playbackRate },
            set: { controller.setPlaybackRate($0) }
        )
    }

    /// "1x", "0.5x", "1.25x" — %g drops trailing zeros so whole rates stay tidy.
    private func rateLabel(_ rate: Float) -> String {
        "\(String(format: "%g", Double(rate)))x"
    }

    private var pipButton: some View {
        Button { pip.toggle() } label: {
            Image(systemName: pip.isActive ? "pip.exit" : "pip.enter")
                .font(.title3)
        }
        .tint(.primary)
        .disabled(!pip.isPossible)
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
