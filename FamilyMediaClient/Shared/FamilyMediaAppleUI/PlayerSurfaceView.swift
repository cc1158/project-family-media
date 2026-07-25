import AVFoundation
import SwiftUI
import UIKit

struct PlayerSurfaceView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerLayerContainerView {
        let view = PlayerLayerContainerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerContainerView, context: Context) {
        uiView.player = player
    }

    static func dismantleUIView(_ uiView: PlayerLayerContainerView, coordinator: Void) {
        uiView.player = nil
    }
}

final class PlayerLayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer? {
        layer as? AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer?.player }
        set { playerLayer?.player = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer?.videoGravity = .resizeAspect
        isAccessibilityElement = true
        accessibilityLabel = "视频画面"
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        playerLayer?.videoGravity = .resizeAspect
        isAccessibilityElement = true
        accessibilityLabel = "视频画面"
    }
}
