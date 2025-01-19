import Foundation
import AVFoundation

class VideoStateObserver: NSObject {
    // MARK: - Properties
    
    /// Closure to handle play state changes
    private let onPlayStateChanged: (Bool) -> Void
    
    /// Weak reference to the player being observed
    private weak var observedPlayer: AVPlayer?
    
    /// Context for KVO observation
    private let observerContext = UnsafeMutableRawPointer.allocate(
        byteCount: 1,
        alignment: 1
    )
    
    /// Track if we're currently observing to prevent double-registration
    private var isObserving: Bool = false
    
    // MARK: - Initialization
    
    init(onPlayStateChanged: @escaping (Bool) -> Void) {
        self.onPlayStateChanged = onPlayStateChanged
        super.init()
    }
    
    // MARK: - Observer Management
    
    /// Start observing an AVPlayer's rate changes
    /// - Parameter player: The AVPlayer to observe
    func startObserving(_ player: AVPlayer) {
        // Remove any existing observation first
        if let currentPlayer = observedPlayer {
            stopObserving(currentPlayer)
        }
        
        guard !isObserving else { return }
        
        player.addObserver(
            self,
            forKeyPath: #keyPath(AVPlayer.rate),
            options: [.new, .initial],
            context: observerContext
        )
        
        observedPlayer = player
        isObserving = true
        
        // Initial state update
        let isPlaying = player.rate != 0
        DispatchQueue.main.async { [weak self] in
            self?.onPlayStateChanged(isPlaying)
        }
    }
    
    /// Stop observing an AVPlayer's rate changes
    /// - Parameter player: The AVPlayer to stop observing
    func stopObserving(_ player: AVPlayer?) {
        guard isObserving,
              let player = player,
              player === observedPlayer else { return }
        
        player.removeObserver(
            self,
            forKeyPath: #keyPath(AVPlayer.rate),
            context: observerContext
        )
        
        observedPlayer = nil
        isObserving = false
    }
    
    // MARK: - KVO Observer Method
    
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        // Verify this is our observation
        guard context == observerContext else {
            super.observeValue(
                forKeyPath: keyPath,
                of: object,
                change: change,
                context: context
            )
            return
        }
        
        guard keyPath == #keyPath(AVPlayer.rate),
              let player = object as? AVPlayer,
              player === observedPlayer else { return }
        
        let isPlaying = player.rate != 0
        DispatchQueue.main.async { [weak self] in
            self?.onPlayStateChanged(isPlaying)
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        if let player = observedPlayer {
            stopObserving(player)
        }
        observerContext.deallocate()
    }
}
