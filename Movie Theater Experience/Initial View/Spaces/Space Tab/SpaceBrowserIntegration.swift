import SwiftUI
import RealityKit
import FirebaseFirestore

struct SpaceBrowserIntegration: View {
    @EnvironmentObject private var selectedSpace: SelectedSpace
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var windowManager: WindowManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    
    @ObservedObject private var service = SpaceService.shared
    @StateObject private var spaceViewModel = VolumetricSpaceViewModel()
    
    @State private var showJoinFailedAlert = false
    @State private var isLoadingSpace = false
    @State private var loadError: Error?
    @State private var loadingProgress: Double = 0.0
    @State private var loadingMessage: String = ""
    @State private var activeSpaceID: String? = nil
    @State private var loadingTask: Task<Void, Never>? = nil  // Track the loading task
    @State private var isCancelled = false  // Track cancellation state

    // MARK: - Child Views

    // MARK: - Card View
    private func cardView(for space: SpaceData, index: Int) -> some View {
        let isHighlighted: Bool = {
            guard let spaceIDString = space.id else { return false }
            
            if let selectedID = appModel.selectedSpace?.id {
                return activeSpaceID == spaceIDString || selectedID == spaceIDString
            } else {
                return activeSpaceID == spaceIDString
            }
        }()
        
        return SpaceCard(
            space: space,
            isHighlighted: isHighlighted,
            onInfoTapped: {
                // Info button action - just log or handle attribution
                print("ℹ️ Info tapped for \(space.spaceName)")
            },
            onCardTapped: {
                // Card tap action - enter immersive space
                if let spaceIDString = space.id {
                    activeSpaceID = spaceIDString
                    loadingTask = Task {
                        await enterImmersiveSpace(space: space)
                    }
                }
            }
        )
        .opacity(isLoadingSpace ? 0.6 : 1.0)
        .allowsHitTesting(!isLoadingSpace)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .modifier(AnimatedAppearanceModifier(index: index, activeSpaceID: activeSpaceID, isLoading: isLoadingSpace))
        .modifier(ConditionalCardHoverModifier())
    }
    
    private struct AnimatedAppearanceModifier: ViewModifier {
        let index: Int
        let activeSpaceID: String?
        let isLoading: Bool
        
        func body(content: Content) -> some View {
            content
                .animation(.spring(duration: 0.5).delay(Double(index) * 0.05), value: index)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: activeSpaceID)
                .animation(.easeInOut(duration: 0.2), value: isLoading)
        }
    }
    
    private struct ConditionalCardHoverModifier: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 18.0, visionOS 2.0, *) {
                content.interactiveCardHover(cornerRadius: 24)
            } else {
                content
            }
        }
    }
    
    private var spaceGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 320, maximum: 320), spacing: 40)
                ],
                spacing: 32
            ) {
                ForEach(Array(service.spaces.enumerated()), id: \.element.id) { index, space in
                    cardView(for: space, index: index)
                        .frame(width: 320, height: 280)  // Enforce consistent card size
                }
            }
            .padding(32)
        }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white)
                    .symbolEffect(.pulse, options: .repeating)
                
                Text(loadingMessage)
                    .font(.headline)
                    .foregroundColor(.white)
                    .animation(.easeInOut, value: loadingMessage)
                
                ProgressView(value: loadingProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(.white)
                    .scaleEffect(y: 2)
                    .frame(width: 200)
                
                Text("\(Int(loadingProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .monospacedDigit()
                
                Button("Cancel") {
                    cancelLoading()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.red)
                .padding(.top, 10)
            }
            .padding(40)
            .background(.ultraThinMaterial.opacity(0.9))
            .cornerRadius(20)
            .shadow(radius: 10)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: isLoadingSpace)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack {
            if service.isLoading {
                ProgressView("Loading spaces...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = service.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        service.fetchSpaces()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.spaces.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No Spaces Available")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("No volumetric spaces found in the database.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                spaceGrid
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    service.fetchSpaces()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoadingSpace)
            }
        }
        .onAppear {
            if service.spaces.isEmpty {
                service.fetchSpaces()
            }
        }
        .alert("Could Not Join Space", isPresented: $showJoinFailedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please go to the Chat Settings and set a username before joining a shared space. This is so you have a username.")
        }
        .overlay {
            if isLoadingSpace { loadingOverlay }
        }
    }
    
    // MARK: - Functions
    
    @MainActor
    private func enterImmersiveSpace(space: SpaceData) async {
        guard !appModel.username.isEmpty else {
            showJoinFailedAlert = true
            return
        }
        
        // Reset cancellation flag
        isCancelled = false
        isLoadingSpace = true
        loadError = nil
        loadingProgress = 0.0
        loadingMessage = "Initializing..."
        
        do {
            // Check for cancellation before each step
            try Task.checkCancellation()
            guard !isCancelled else { throw CancellationError() }
            
            await updateProgress(0.1, message: "Preparing space...")
            appModel.selectedSpace = space
            try await Task.sleep(for: .milliseconds(200))
            
            try Task.checkCancellation()
            guard !isCancelled else { throw CancellationError() }
            
            await updateProgress(0.2, message: "Downloading \(space.spaceName)...")
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.loadSpaceEntity(space: space)
                }
                try await group.waitForAll()
            }
            
            try Task.checkCancellation()
            guard !isCancelled else { throw CancellationError() }
            
            await updateProgress(0.5, message: "Processing 3D content...")
            try await Task.sleep(for: .milliseconds(300))
            
            try Task.checkCancellation()
            guard !isCancelled else { throw CancellationError() }
            
            await updateProgress(0.6, message: "Preparing immersive environment...")
            let success = await appModel.switchToSpace(appModel.spacesID)
            guard success else {
                throw SpaceLoadError.transitionFailed
            }
            
            try Task.checkCancellation()
            guard !isCancelled else { throw CancellationError() }
            
            await updateProgress(0.7, message: "Setting up scene...")
            try await Task.sleep(for: .milliseconds(200))
            
            try Task.checkCancellation()
            guard !isCancelled else { throw CancellationError() }
            
            await updateProgress(0.8, message: "Entering space...")
            await openImmersiveSpace(id: appModel.spacesID)
            
            await updateProgress(0.9, message: "Finalizing...")
            openCompanionWindows()
            await updateProgress(1.0, message: "Welcome to \(space.spaceName)!")
            try await Task.sleep(for: .milliseconds(500))
            
            dismissWindow(id: "mainContent")
            print("🚪 Dismissed ContentView window")
            
        } catch is CancellationError {
            print("⚠️ Loading was cancelled by user")
            activeSpaceID = nil
            appModel.selectedSpace = nil
        } catch {
            print("❌ Failed to enter immersive space: \(error)")
            loadError = error
            activeSpaceID = nil
            appModel.selectedSpace = nil
            
            if !isCancelled {
                await showErrorAlert(error: error)
            }
        }
        
        withAnimation {
            isLoadingSpace = false
            loadingTask = nil
        }
    }
    
    @MainActor
    private func updateProgress(_ progress: Double, message: String) async {
        guard !isCancelled else { return }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            self.loadingProgress = progress
            self.loadingMessage = message
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
    
    private func loadSpaceEntity(space: SpaceData) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            // Simulate progress with a timer
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                if self.isCancelled {
                    timer.invalidate()
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: CancellationError())
                    }
                    return
                }
                
                Task { @MainActor in
                    if self.loadingProgress < 0.45 {
                        self.loadingProgress = min(self.loadingProgress + 0.01, 0.45)
                    }
                }
            }
            
            SpaceService.shared.loadSpace(from: space) { result in
                progressTimer.invalidate()
                
                guard !hasResumed else { return }
                hasResumed = true
                
                if self.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                
                switch result {
                case .success(let entity):
                    Task { @MainActor in
                        self.loadingProgress = 0.5
                    }
                    SpacesEntityWrapper.shared.setEntity(entity.clone(recursive: true))
                    SpacesEntityWrapper.shared.setSpaceEntity(entity.clone(recursive: true))
                    SpacesEntityWrapper.shared.setActiveSceneEntity(entity.clone(recursive: true))
                    print("✅ Space entity loaded and stored")
                    continuation.resume()
                    
                case .failure(let error):
                    print("❌ Failed to load space entity: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func cancelLoading() {
        print("🛑 Cancel button pressed")
        
        // Set cancellation flag
        isCancelled = true
        
        // Cancel the loading task if it exists
        loadingTask?.cancel()
        loadingTask = nil
        
        // Reset UI state
        withAnimation {
            isLoadingSpace = false
            loadingProgress = 0.0
            loadingMessage = ""
            activeSpaceID = nil
        }
        
        // Clear selected space
        appModel.selectedSpace = nil
    }
    
    private func openCompanionWindows() {
        print("🪟 Opened companion windows for immersive space")
    }
    
    @MainActor
    private func showErrorAlert(error: Error) async {
        let alert = UIAlertController(
            title: "Failed to Load Space",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
}

// MARK: - Error Types

enum SpaceLoadError: LocalizedError {
    case transitionFailed
    case entityLoadFailed
    
    var errorDescription: String? {
        switch self {
        case .transitionFailed:
            return "Failed to transition to immersive space"
        case .entityLoadFailed:
            return "Failed to load space content"
        }
    }
}

extension View {
    @ViewBuilder
    func ifAvailableiOS18<Content: View>(
        @ViewBuilder transform: (Self) -> Content
    ) -> some View {
        if #available(iOS 18.0, visionOS 2.0, *) {
            transform(self)
        } else {
            self
        }
    }
}
