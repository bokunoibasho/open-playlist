import AVKit
import SwiftUI

/// Displays the `AVPlayerLayer` owned by `PictureInPictureController` so video
/// shows inline in the Now Playing surface. The layer is *not* owned here — it
/// lives on the PiP controller so it can outlast this view (and keep PiP
/// running after the sheet is dismissed). This view just hosts and resizes it.
struct PlayerLayerView: UIViewRepresentable {
    let pip: PictureInPictureController

    func makeUIView(context: Context) -> PlayerHostUIView {
        let view = PlayerHostUIView()
        view.backgroundColor = .black
        view.hostedLayer = pip.playerLayer
        return view
    }

    func updateUIView(_ uiView: PlayerHostUIView, context: Context) {
        uiView.hostedLayer = pip.playerLayer
    }
}

/// A plain `UIView` that parents a borrowed `AVPlayerLayer` and keeps it sized
/// to its bounds. Re-parents on assignment so the same layer can move between
/// hosts as the Now Playing sheet appears and disappears.
final class PlayerHostUIView: UIView {
    var hostedLayer: AVPlayerLayer? {
        didSet {
            guard hostedLayer !== oldValue else { return }
            oldValue?.removeFromSuperlayer()
            if let hostedLayer {
                hostedLayer.frame = bounds
                layer.addSublayer(hostedLayer)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostedLayer?.frame = bounds
    }
}
