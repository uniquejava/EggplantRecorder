import AVFoundation
import AppKit
import SwiftUI

struct PlayerPreviewView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerPreviewNSView {
        let view = PlayerPreviewNSView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerPreviewNSView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

final class PlayerPreviewNSView: NSView {
    private let playerLayer = AVPlayerLayer()

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
