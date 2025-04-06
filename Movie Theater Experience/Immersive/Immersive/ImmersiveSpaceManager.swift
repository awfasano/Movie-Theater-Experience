import SwiftUI
import RealityKit

@MainActor
class ImmersiveSpaceManager: ObservableObject {
    // MARK: - Singleton
    static let shared = ImmersiveSpaceManager()
    
    // MARK: - Properties
    private(set) var state: ImmersiveSpaceState = .closed
    private(set) var isCleaningUp = false
    
    // MARK: - Environment Properties
    var dismissImmersiveSpace: () async -> Void = { }
    var dismissWindow: (String) -> Void = { _ in }
    var openWindow: (String) -> Void = { _ in }
    var openImmersiveSpace: () async -> Bool = { return false }

    // MARK: - Private Properties
    private var delegates: [WeakDelegate] = []
    private var cleanupTask: Task<Void, Never>?
    private var activeWindows: Set<String> = []
    
    @Published var initialUserPosition: SIMD3<Float> = SIMD3<Float>(0, 1.6, 0)
    @Published var initialUserOrientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    
    // MARK: - Private Init
    private init() {}
    
    // MARK: - Configuration
    func configure(
        dismissImmersiveSpace: @escaping () async -> Void,
        dismissWindow: @escaping (String) -> Void,
        openWindow: @escaping (String) -> Void,
        openImmersiveSpace: @escaping () async -> Bool
    ) {
        self.dismissImmersiveSpace = dismissImmersiveSpace
        self.dismissWindow = dismissWindow
        self.openWindow = openWindow
        self.openImmersiveSpace = openImmersiveSpace
    }
    
    // MARK: - State Management
    func prepareForOpening() async -> Bool {
        print("🎬 Preparing immersive space for opening")
        
        guard case .closed = state else {
            print("❌ Cannot prepare for opening: space is not closed (current state: \(state))")
            return false
        }
        
        // Wait for any ongoing cleanup
        if let cleanupTask = cleanupTask {
            print("⏳ Waiting for existing cleanup task to complete")
            await cleanupTask.value
        }
        
        // Double check the cleanup flag
        while isCleaningUp {
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        state = .transitioning(.opening)
        delegates.forEach { $0.delegate?.immersiveSpaceWillOpen() }
        
        return true
    }
    
    func handleOpenSuccess() {
        print("✅ Space opened successfully")
        state = .open
        delegates.forEach { $0.delegate?.immersiveSpaceDidOpen() }
        
        // Make sure nav bar opens with a slight delay to ensure proper sequencing
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            if !activeWindows.contains("navBar") {
                print("🪟 Opening nav bar window")
                openWindow("navBar")
                activeWindows.insert("navBar")
            }
        }
    }
    
    func handleOpenFailure() {
        print("❌ Failed to open space")
        state = .closed
        delegates.forEach { $0.delegate?.immersiveSpaceDidFailToOpen() }
    }
    
    func initiateCleanup() async {
        guard case .open = state else {
            print("⚠️ Cannot cleanup: space is not open (current state: \(state))")
            return
        }
        
        print("🧹 Starting immersive space cleanup")
        
        state = .transitioning(.cleaning)
        isCleaningUp = true
        
        // Cancel any existing cleanup
        cleanupTask?.cancel()
        
        // Create new cleanup task
        cleanupTask = Task { [weak self] in
            guard let self = self else { return }
            
            defer {
                Task { @MainActor in
                    self.isCleaningUp = false
                    if self.state.isTransitioning {
                        self.state = .closed
                    }
                }
            }
            
            do {
                try await self.performCleanupTasks()
                if !Task.isCancelled {
                    self.delegates.forEach { $0.delegate?.immersiveSpaceDidClose() }
                }
            } catch {
                print("❌ Cleanup failed with error: \(error)")
                self.delegates.forEach { $0.delegate?.immersiveSpaceDidClose() }
            }
        }
        
        // Wait for cleanup to complete
        await cleanupTask?.value
    }
    
    // MARK: - Window Management
    private func dismissAllWindows() async {
        print("🪟 Dismissing content windows")
        let windowIds = ["chatWindow", "emojiWindow", "movieWindow", "seatMap", "navBar", "tabBar"]
        
        for windowId in windowIds {
            if activeWindows.contains(windowId) {
                dismissWindow(windowId)
                activeWindows.remove(windowId)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
    
    private func dismissNavBar() {
        print("🪟 Dismissing nav bar")
        if activeWindows.contains("navBar") {
            dismissWindow("navBar")
            activeWindows.remove("navBar")
        }
    }
    
    private func showTabBar() {
        print("🪟 Showing tab bar")
        if !activeWindows.contains("tabBar") {
            openWindow("tabBar")
            activeWindows.insert("tabBar")
        }
    }
    
    // MARK: - Cleanup Tasks
    private func performCleanupTasks() async throws {
        print("🧹 Starting cleanup tasks")
        
        // 1. Stop any ongoing videos
        if let videoManager = TheatreEntityWrapper.shared.videoPlayerManager {
            print("📺 Stopping video playback")
            VideoSyncService.shared.handlePlayPause(isPlaying: false)  // Use VideoSyncService instead
            videoManager.clearAllResources()
        }
        
        // 2. Wait for video cleanup
        try? await Task.sleep(for: .milliseconds(100))
        
        // 3. Clean up entity wrapper
        await TheatreEntityWrapper.shared.cleanup()
        
        // 4. Wait for entity cleanup
        try? await Task.sleep(for: .milliseconds(100))
        
        // 5. Reset shared state
        print("🔄 Resetting shared state")
        SharedSeatSelection.shared.selectedSeatEntity = nil
        
        // 6. Dismiss all windows including nav bar
        await dismissAllWindows()
        
        // 7. Dismiss immersive space
        await dismissImmersiveSpace()
        
        // 8. Wait for dismissals
        try? await Task.sleep(for: .milliseconds(200))
        
        // 9. Show tab bar if not already showing
        if !activeWindows.contains("tabBar") {
            showTabBar()
        }
        
        print("✅ Cleanup tasks completed")
    }
    
    // MARK: - Delegate Management
    func addDelegate(_ delegate: ImmersiveSpaceDelegate) {
        delegates.append(WeakDelegate(delegate))
        // Clean up any nil delegates
        delegates = delegates.filter { $0.delegate != nil }
    }
    
    func removeDelegate(_ delegate: ImmersiveSpaceDelegate) {
        delegates.removeAll { $0.delegate === delegate }
    }
    
    func setInitialUserPosition(position: SIMD3<Float>, orientation: simd_quatf) {
        initialUserPosition = position
        initialUserOrientation = orientation
    }
}
