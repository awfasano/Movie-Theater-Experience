import SwiftUI
import RealityKit
import FirebaseFirestore

struct SpaceBrowserIntegration: View {
    @EnvironmentObject private var selectedSpace: SelectedSpace
    @Environment(AppModel.self) private var appModel

    @EnvironmentObject private var windowManager: WindowManager
    @Environment(\.openWindow) private var openWindow

    @ObservedObject private var service = SpaceService.shared

    @State private var spaceFilter: SpaceFilter = .all

    private enum SpaceFilter: String, CaseIterable {
        case all = "All"
        case theaters = "Theaters"
        case ambient = "Ambient"
    }

    private var filteredSpaces: [SpaceData] {
        switch spaceFilter {
        case .all:
            return service.spaces
        case .theaters:
            return service.spaces.filter { space in
                !(space.tags?.contains("ambient") == true)
            }
        case .ambient:
            return service.spaces.filter { space in
                space.tags?.contains("ambient") == true
            }
        }
    }

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
                VStack(spacing: 0) {
                    Picker("Filter", selection: $spaceFilter) {
                        ForEach(SpaceFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    if filteredSpaces.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: spaceFilter == .ambient ? "sparkles" : "cube.transparent")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No \(spaceFilter.rawValue) Spaces")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("No spaces match this filter.")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 16) {
                                ForEach(filteredSpaces) { space in
                                    if space.tags?.contains("ambient") == true {
                                        AmbientSpaceCard(space: space)
                                            .onTapGesture {
                                                appModel.selectedSpace = space
                                                openVolumetricView()
                                            }
                                    } else {
                                        SpaceCard(space: space)
                                            .onTapGesture {
                                                appModel.selectedSpace = space
                                                openVolumetricView()
                                            }
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    service.fetchSpaces()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            if service.spaces.isEmpty {
                service.fetchSpaces()
            }
        }
    }
    
    private func openVolumetricView() {
        // Use the SwiftUI environment's openWindow directly
        openWindow(id: "volume")
    }
}
