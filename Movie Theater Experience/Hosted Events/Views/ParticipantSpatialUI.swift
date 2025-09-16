import Foundation
import SwiftUI
import simd

struct ParticipantSpatialUI: View {
    let tableNumber: Int
    @EnvironmentObject private var personaManager: PersonaTableManager
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @EnvironmentObject private var triviaGameManager: TriviaGameManager
    @State private var showHostAnnouncement = false

    var body: some View {
        // Get current user, event, and question context
        guard let currentUserId = AppModel.shared.userID as String?,
            let eventId = hostedEventManager.currentEvent?.id,
            let currentQuestion = triviaGameManager.currentQuestion else {
            return AnyView(Text("Joining table...").font(.title2))
        }
        // Create manager for this table/question/user
        let tableManager = TableCollaborationManager(
            tableNumber: tableNumber,
            maxVotes: 4,
            question: currentQuestion,
            userId: currentUserId,
            eventId: eventId
        )
        return AnyView(
            ZStack {
                TableQuestionPanel(
                    question: currentQuestion,
                    timeRemaining: triviaGameManager.timeRemaining,
                    tableNumber: tableNumber
                )
                .position3D(calculateQuestionPanelPosition())

                CollaborativeAnswerView(
                    question: currentQuestion,
                    tableNumber: tableNumber
                )
                .position3D(calculatePersonalInterfacePosition())

                TableDashboard(tableNumber: tableNumber)
                    .position3D(calculateDashboardPosition())

                TriviaEmojiReactions(tableNumber: tableNumber)
                    .position3D(calculateEmojiButtonsPosition())

                HostAnnouncementOverlay()
            }
            .environmentObject(tableManager)
        )
    }

    private func calculateQuestionPanelPosition() -> SIMD3<Float> {
        guard let tablePosition = personaManager.getTablePosition(tableNumber) else {
            return SIMD3<Float>(0, 2, 0)
        }
        return SIMD3<Float>(tablePosition.x, tablePosition.y + 1.5, tablePosition.z)
    }

    private func calculatePersonalInterfacePosition() -> SIMD3<Float> {
        guard let userPosition = personaManager.getCurrentUserPosition() else {
            return SIMD3<Float>(0, 1, -1)
        }
        return SIMD3<Float>(userPosition.x, userPosition.y + 0.5, userPosition.z - 0.8)
    }

    private func calculateDashboardPosition() -> SIMD3<Float> {
        guard let tablePosition = personaManager.getTablePosition(tableNumber) else {
            return SIMD3<Float>(1, 1, 0)
        }
        return SIMD3<Float>(tablePosition.x + 1.2, tablePosition.y + 0.8, tablePosition.z)
    }

    private func calculateEmojiButtonsPosition() -> SIMD3<Float> {
        guard let tablePosition = personaManager.getTablePosition(tableNumber) else {
            return SIMD3<Float>(0, 0.7, 1)
        }
        return SIMD3<Float>(tablePosition.x, tablePosition.y + 0.7, tablePosition.z + 1)
    }
}
