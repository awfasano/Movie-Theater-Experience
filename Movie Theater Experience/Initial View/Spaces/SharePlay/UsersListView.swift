import Foundation
import SwiftUI

struct UserListView: View {
    @Environment(AppModel.self) private var appModel
    @ObservedObject private var spaceService = SpaceService.shared
    @ObservedObject private var sharePlayManager = SharePlayManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // Mock users for now since the property is commented out in SpaceService
    @State private var usersInCurrentSpace: [SharePlayUser] = []

    var body: some View {
        VStack(spacing: 16) {
            Text("People in \(appModel.currentActiveSpace ?? "Space")")
                .font(.largeTitle)
                .padding()

            Button {
                Task {
                    do {
                        try await sharePlayManager.startPublicSpaceActivity()
                    } catch {
                        print("Failed to start public space activity: \(error)")
                    }
                }
                dismiss()
            } label: {
                Label("Join Public Conversation", systemImage: "person.3.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            
            Divider()

            ScrollView {
                if usersInCurrentSpace.isEmpty {
                    Text("You're the first one here!").padding().foregroundStyle(.secondary)
                } else {
                    ForEach(usersInCurrentSpace, id: \.id) { user in
                        HStack {
                            Image(systemName: "person.circle.fill").font(.largeTitle).foregroundStyle(.secondary)
                            Text(user.name).font(.title3)
                            Spacer()
                            Button {
                                Task {
                                    do {
                                        try await sharePlayManager.startDirectCallActivity()
                                    } catch {
                                        print("Failed to start direct call activity: \(error)")
                                    }
                                }
                                dismiss()
                            } label: {
                                Image(systemName: "phone.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }
                }
            }
        }
        .padding()
        .glassBackgroundEffect()
        .onAppear {
            // Load sample users for demonstration
            // You can replace this with actual data loading from spaceService when implemented
            loadSampleUsers()
        }
    }
    
    private func loadSampleUsers() {
        // Mock data for demonstration - replace with actual service call when ready
        usersInCurrentSpace = [
            SharePlayUser(id: "user1", name: "Alice Johnson"),
            SharePlayUser(id: "user2", name: "Bob Smith"),
            SharePlayUser(id: "user3", name: "Carol Davis")
        ]
    }
}
