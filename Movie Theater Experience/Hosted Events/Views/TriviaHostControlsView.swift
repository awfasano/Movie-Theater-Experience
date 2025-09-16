import SwiftUI

struct TriviaHostControlsView: View {
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @EnvironmentObject private var triviaGameManager: TriviaGameManager
    @EnvironmentObject private var personaManager: PersonaTableManager

    var body: some View {
        TabView {
            gameControlsTab
            participantManagementTab
            scoringTab
            broadcastTab
        }
    }

    private var gameControlsTab: some View {
        VStack {
            currentQuestionDisplay
            questionControls
            timerDisplay
        }
    }

    private var participantManagementTab: some View {
        VStack {
            participantList
            tableAssignmentControls
            personaPositionDebugView
        }
    }

    private var scoringTab: some View {
        Text("Scoring controls here")
    }

    private var broadcastTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Current Notification: \(hostedEventManager.gameState?.trigger ?? "None")")
                .font(.headline)
                .padding(.bottom, 8)
            Text("Send Notification to Participants:")
                .font(.title3.bold())
            ForEach(hostedEventManager.notificationActions, id: \.self) { action in
                Button(action) {
                    Task { await hostedEventManager.triggerNotification(action) }
                }
                .buttonStyle(.borderedProminent)
                .padding(.vertical, 4)
            }
        }
        .padding()
    }

    // Stubs (fill in as needed)
    private var currentQuestionDisplay: some View { Text("Current Question") }
    private var questionControls: some View { Text("Question Controls") }
    private var timerDisplay: some View { Text("Timer") }
    private var participantList: some View { Text("Participant List") }
    private var tableAssignmentControls: some View { Text("Table Assignment Controls") }
    private var personaPositionDebugView: some View { Text("Persona Position Debug") }
}
