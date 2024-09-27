import SwiftUI
import AVKit
import AVFoundation

struct MovieWindow: View {
    @State private var player = AVPlayer()
    @State private var aspectRatio: AVLayerVideoGravity = .resizeAspect
    @State private var isFullScreen = false
    @State private var dragOffset = CGSize.zero

    var body: some View {
        VStack {
            VideoPlayerView(player: player, videoGravity: aspectRatio)
                .frame(width: isFullScreen ? nil : 500, height: isFullScreen ? nil : 350)
                .edgesIgnoringSafeArea(isFullScreen ? .all : [])
                .offset(x: dragOffset.width, y: dragOffset.height)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            if !isFullScreen {
                                self.dragOffset = gesture.translation
                            }
                        }
                        .onEnded { _ in
                            if !isFullScreen {
                                self.dragOffset = .zero // Reset after dragging
                            }
                        }
                )
                .onAppear {
                    if let videoURL = Bundle.main.url(forResource: "spiderman", withExtension: "mp4") {
                        player = AVPlayer(url: videoURL)
                        player.play()
                    } else {
                        print("Can't find video URL")
                    }
                }
                .onDisappear {
                    // Stop playback when the window is closed
                    player.pause()
                    player.replaceCurrentItem(with: nil)
                }

            HStack {
                Button("Toggle Aspect Ratio") {
                    toggleAspectRatio()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)

                Button("Toggle Full Screen") {
                    toggleFullScreen()
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding()
        }
        .padding()
    }

    func toggleAspectRatio() {
        switch aspectRatio {
        case .resizeAspect:
            aspectRatio = .resizeAspectFill
        case .resizeAspectFill:
            aspectRatio = .resize
        default:
            aspectRatio = .resizeAspect
        }
    }

    func toggleFullScreen() {
        withAnimation {
            isFullScreen.toggle()
        }
    }
}

struct VideoPlayerView: UIViewRepresentable {
    var player: AVPlayer
    var videoGravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> UIView {
        return PlayerView(player: player, videoGravity: videoGravity)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as! PlayerView).playerLayer.videoGravity = videoGravity
    }
}

class PlayerView: UIView {
    var playerLayer: AVPlayerLayer

    init(player: AVPlayer, videoGravity: AVLayerVideoGravity) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = videoGravity
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
