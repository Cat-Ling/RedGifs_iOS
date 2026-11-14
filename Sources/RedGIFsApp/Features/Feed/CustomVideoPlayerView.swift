import AVFoundation
import SwiftUI
import UIKit

struct CustomVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer?
    let videoGravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerContainerUIView {
        let view = PlayerContainerUIView()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.playerLayer.backgroundColor = UIColor.clear.cgColor
        view.playerLayer.masksToBounds = true
        view.playerLayer.videoGravity = videoGravity
        view.playerLayer.player = player
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        if uiView.playerLayer.videoGravity != videoGravity {
            uiView.playerLayer.videoGravity = videoGravity
        }
    }
}

final class PlayerContainerUIView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        // Guaranteed by layerClass override above.
        layer as! AVPlayerLayer
    }
}
