import Foundation
import SwiftUI

struct UserListView: View {
    @Environment(AppModel.self) private var appModel
    @ObservedObject private var spaceService = SpaceService.shared
    @ObservedObject private var sharePlayManager = SharePlayManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("People in \(appModel.selectedSpace?.spaceName ?? "Space")")
                .font(.largeTitle)
                .padding()

            Button {
                if let space = appModel.selectedSpace {
                    sharePlayManager.startPublicCall(for: space)
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
                if spaceService.usersInCurrentSpace.isEmpty {
                    Text("You're the first one here!").padding().foregroundStyle(.secondary)
                } else {
                    ForEach(spaceService.usersInCurrentSpace, id: \.id) { user in
                        HStack {
                            Image(systemName: "person.circle.fill").font(.largeTitle).foregroundStyle(.secondary)
                            Text(user.name).font(.title3)
                            Spacer()
                            Button {
                                if let space = appModel.selectedSpace {
                                    sharePlayManager.startDirectCall(with: user, in: space)
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
            if let spaceId = appModel.selectedSpace?.id {
                Task {
                    await spaceService.fetchUsersInSpace(spaceId: spaceId)
                }
            }
        }
    }
}
