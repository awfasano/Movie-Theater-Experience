import SwiftUI

struct ToggleImmersiveSpaceButton: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    
    var body: some View {
        Button {
            Task { @MainActor in
                switch appModel.immersiveSpaceState {
                    case .open:
                        appModel.immersiveSpaceState = .inTransition
                        // Don't dismiss the nav bar, just handle the movie window
                        await dismissImmersiveSpace()
                        
                        // Check if we should show the movie window
                        if !appModel.isMovieWindowOpen, let _ = appModel.selectedVideoURL {
                            appModel.isMovieWindowOpen = true
                            openWindow(id: "movieWindow")
                        }
                        // State will be set to .closed in ImmersiveView.onDisappear()

                    case .closed:
                        appModel.immersiveSpaceState = .inTransition
                        
                        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                            case .opened:
                                // State will be set to .open in ImmersiveView.onAppear()
                                break
                            
                            case .userCancelled, .error:
                                fallthrough
                            @unknown default:
                                appModel.immersiveSpaceState = .closed
                        }
                        
                    case .inTransition:
                        // Button is disabled in this state
                        break
                }
            }
        } label: {
            Text(appModel.immersiveSpaceState == .open ? "Hide Immersive Space" : "Show Immersive Space")
        }
        .disabled(!appModel.canTransitionImmersiveSpace())
        .animation(.none, value: 0)
        .fontWeight(.semibold)
    }
}
