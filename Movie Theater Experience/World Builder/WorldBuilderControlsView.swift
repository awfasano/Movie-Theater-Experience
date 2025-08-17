import SwiftUI

struct WorldBuilderControlsView: View {
    @EnvironmentObject private var worldBuilder: WorldBuilderManager
    @StateObject private var envManager = EnvironmentManager.shared
    
    @State private var selectedCategory: WorldCategory? = nil

    var body: some View {
        VStack(spacing: 20) {
            header

            if let category = selectedCategory {
                environmentList(for: category)
            } else {
                categorySelectionView
            }
            
            Spacer()
        }
        .padding(20)
        .frame(width: 400)
        .glassBackgroundEffect()
        .onAppear {
            Task { await envManager.fetchAllEnvironments() }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .font(.largeTitle)
                .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
            Text("World Builder")
                .font(.title)
                .fontWeight(.bold)
            Spacer()
        }
    }
    
    // MARK: - Category Selection
    private var categorySelectionView: some View {
        VStack(spacing: 16) {
            Text("Choose World Type").font(.headline)
            ForEach(WorldCategory.allCases, id: \.self) { cat in
                Button {
                    withAnimation { selectedCategory = cat }
                } label: {
                    Text(cat.rawValue)
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
    }
    
    // MARK: - List of Environments
    @ViewBuilder
    private func environmentList(for category: WorldCategory) -> some View {
        VStack {
            HStack {
                Button {
                    withAnimation { selectedCategory = nil }
                } label: {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                Spacer()
                Text(category.rawValue).font(.headline)
                Spacer()
            }
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 12) {
                    defaultCard(for: category)

                    let available = envManager.availableEnvironments.filter {
                        $0.worldCategory == category
                    }

                    if envManager.isLoading {
                        ProgressView()
                    } else {
                        ForEach(available) { env in
                            card(for: env)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Default Basic Environments
    private func defaultCard(for category: WorldCategory) -> some View {
        let preset: EnvironmentPreset =
            category == .open ? .defaultOutdoor : .defaultIndoor
        
        return Button {
            Task { await worldBuilder.loadDefaultEnvironment(preset) }
        } label: {
            HStack {
                Image(systemName: preset.icon)
                    .font(.title)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading) {
                    Text(preset.displayName).font(.headline)
                    Text(preset.description).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Firestore Card
    private func card(for env: EnvironmentData) -> some View {
        Button {
            Task { await worldBuilder.loadEnvironment(env) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(maxWidth: .infinity, minHeight: 80)

                    if let urlString = env.thumbnailUrl,
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:  ProgressView()
                            case .success(let img):
                                img.resizable().scaledToFill()
                            case .failure: Image(systemName: "photo.fill")
                            @unknown default: EmptyView()
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .clipped()
                    } else {
                        Image(systemName: "photo.fill")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                    }
                }
                VStack(alignment: .leading) {
                    Text(env.name).font(.headline)
                    Text(env.description).font(.caption).lineLimit(2).foregroundColor(.secondary)
                }
                .padding([.horizontal, .bottom])
            }
            .background(.thinMaterial)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(worldBuilder.currentEnvironment?.id == env.id ? .blue : .clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
}
