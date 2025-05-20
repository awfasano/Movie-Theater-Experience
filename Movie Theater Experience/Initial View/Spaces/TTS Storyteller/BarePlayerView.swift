//
//  PlayerView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 6/23/25.
//

import Foundation
import SwiftUI
import AVKit

/// Bare video surface with **no** Apple controls.
class BarePlayerView: UIView {          // ← renamed
    private let playerLayer: AVPlayerLayer

    init(player: AVPlayer,
         videoGravity: AVLayerVideoGravity = .resizeAspect) {

        self.playerLayer = AVPlayerLayer(player: player)
        self.playerLayer.videoGravity = videoGravity
        super.init(frame: .zero)
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}


import SwiftUI
import AVKit

struct BarePlayerContainer: UIViewRepresentable {   // new name, no clash
    let player: AVPlayer

    func makeUIView(context: Context) -> BarePlayerView {
        BarePlayerView(player: player)              // same gravity default
    }
    func updateUIView(_ uiView: BarePlayerView, context: Context) { }
}
