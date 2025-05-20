import SwiftUI

struct ToggleImmersiveSpaceButton: View {
    // MARK: - Environment
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) var openWindow
    
    // MARK: - Services
    private let spaceManager = ImmersiveSpaceManager.shared
    private let videoSyncService = VideoSyncService.shared
    
    // MARK: - Body
    var body: some View {
        Button {
            Task { @MainActor in
                switch spaceManager.state {
                case .open:
                    await handleImmersiveSpaceDismissal()
                case .closed:
                    await handleImmersiveSpaceOpening()
                case .transitioning:
                    break // Do nothing while transitioning
                }
            }
        } label: {
            Text(spaceManager.state == .open ? "Hide Immersive Space" : "Show Immersive Space")
        }
        .disabled(spaceManager.state.isTransitioning)
        .animation(.none, value: 0)
        .fontWeight(.semibold)
    }
    
    // MARK: - Private Methods
    private func handleImmersiveSpaceDismissal() async {
        // Prepare for dismissal
        await spaceManager.initiateCleanup()
        
        // Cleanup video sync
        await videoSyncService.cleanup()
        
        // Dismiss the space
        await dismissImmersiveSpace()
        
        // Handle movie window if needed
        if !appModel.isMovieWindowOpen, let _ = appModel.selectedVideoURL {
            try? await Task.sleep(for: .milliseconds(100))
            appModel.isMovieWindowOpen = true
            openWindow(id: "movieWindow")
        }
    }
    
    private func handleImmersiveSpaceOpening() async {
        // Prepare for opening
        guard await spaceManager.prepareForOpening() else { return }
        
        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
        case .opened:
            spaceManager.handleOpenSuccess()
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            spaceManager.handleOpenFailure()
            if !appModel.isMovieWindowOpen, let _ = appModel.selectedVideoURL {
                appModel.isMovieWindowOpen = true
                openWindow(id: "movieWindow")
            }
        }
    }
}

#Preview {
    ToggleImmersiveSpaceButton()
        .environment(AppModel())
}
