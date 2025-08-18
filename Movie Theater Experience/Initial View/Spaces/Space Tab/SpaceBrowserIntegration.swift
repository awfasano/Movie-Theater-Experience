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
    @State private var hoveredSpaceId: String? = nil // Track which space is being looked at

    // MARK: - Child Views

    private var spaceGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 24) {
                ForEach(Array(service.spaces.enumerated()), id: \.element.id) { index, space in
                    SpaceCard(
                        space: space,
                        isHighlighted: hoveredSpaceId == space.id // Pass highlighting state
                    ) {
                        // Define the action for the info button here.
                        // For example, you could open a detail window:
                        // openWindow(value: space.id)
                        print("Info tapped for \(space.spaceName)")
                    }
                    .opacity(isLoadingSpace ? 0.6 : 1.0)
                    .allowsHitTesting(!isLoadingSpace)
                    .onTapGesture {
                        Task {
                            await enterImmersiveSpace(space: space)
                        }
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(_):
                            hoveredSpaceId = space.id
                        case .ended:
                            hoveredSpaceId = nil
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.spring(duration: 0.5).delay(Double(index) * 0.05), value: service.spaces)
                }
            }
            .padding(24)
        }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            // Full screen background to capture all touches
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea(.all)
            
            // Dark background
            Color.black.opacity(0.7)
                .ignoresSafeArea(.all)
            
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
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .padding(.top, 10)
            }
            .padding(40)
            .background(.ultraThinMaterial.opacity(0.9))
            .cornerRadius(20)
            .shadow(radius: 10)
        }
        .zIndex(1000) // Ensure loading overlay is above everything
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: isLoadingSpace)
    }

    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Main content
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
            .zIndex(0) // Ensure main content is below loading overlay
            
            // Loading overlay - only show when loading
            if isLoadingSpace {
                loadingOverlay
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
            Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please go to the Settings app and set a username before joining a shared space.")
        }
    }
    
    // MARK: - Functions
    
    @MainActor
    private func enterImmersiveSpace(space: SpaceData) async {
        guard !appModel.username.isEmpty else {
            showJoinFailedAlert = true
            return
        }
        
        isLoadingSpace = true
        loadError = nil
        loadingProgress = 0.0
        loadingMessage = "Initializing..."
        
        do {
            await updateProgress(0.1, message: "Preparing space...")
            appModel.selectedSpace = space
            try await Task.sleep(for: .milliseconds(200))
            
            await updateProgress(0.2, message: "Downloading \(space.spaceName)...")
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.loadSpaceEntity(space: space) { progress in
                        Task { @MainActor in
                            let mappedProgress = 0.2 + (progress * 0.3)
                            self.loadingProgress = mappedProgress
                        }
                    }
                }
                try await group.waitForAll()
            }
            
            await updateProgress(0.5, message: "Processing 3D content...")
            try await Task.sleep(for: .milliseconds(300))
            
            await updateProgress(0.6, message: "Preparing immersive environment...")
            let success = await appModel.switchToSpace(appModel.spacesID)
            guard success else {
                throw SpaceLoadError.transitionFailed
            }
            
            await updateProgress(0.7, message: "Setting up scene...")
            try await Task.sleep(for: .milliseconds(200))
            
            await updateProgress(0.8, message: "Entering space...")
            await openImmersiveSpace(id: appModel.spacesID)
            
            await updateProgress(0.9, message: "Finalizing...")
            openCompanionWindows()
            await updateProgress(1.0, message: "Welcome to \(space.spaceName)!")
            try await Task.sleep(for: .milliseconds(500))
            
            dismissWindow(id: "mainContent")
            print("🚪 Dismissed ContentView window")
            
        } catch {
            print("❌ Failed to enter immersive space: \(error)")
            loadError = error
            await showErrorAlert(error: error)
        }
        
        withAnimation {
            isLoadingSpace = false
        }
    }
    
    @MainActor
    private func updateProgress(_ progress: Double, message: String) async {
        withAnimation(.easeInOut(duration: 0.3)) {
            self.loadingProgress = progress
            self.loadingMessage = message
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
    
    private func loadSpaceEntity(space: SpaceData, progressHandler: @escaping (Double) -> Void) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                let currentProgress = self.loadingProgress
                if currentProgress < 0.45 {
                    progressHandler((currentProgress - 0.2) / 0.3 + 0.05)
                }
            }
            
            SpaceService.shared.loadSpace(from: space) { result in
                progressTimer.invalidate()
                
                switch result {
                case .success(let entity):
                    progressHandler(1.0)
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
        withAnimation {
            isLoadingSpace = false
            loadingProgress = 0.0
            loadingMessage = ""
        }
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

// MARK: - Error Enum

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
