import SwiftUI
import FirebaseFirestore

// This extends your existing ChatViewModel to handle spaces data
@MainActor
class SpacesChatViewModel: ChatViewModel {
    // MARK: - Properties
    
    // The spaces manager to handle Firebase operations for spaces
    private let spacesManager = SpacesChatManager.shared
    private var updateTask: Task<Void, Never>?
    
    private let appModel = AppModel.shared

    
    // Shadow storage for messages that we will return in the override
    private var spacesMessages: [ChatMessage] = []
    
    // MARK: - Initialization
    
    // Instead of eventId and date, initialize with spaceId
    init(spaceId: String) {
        // Create a dummy FirebaseEventManager that won't be used
        let dummyEventManager = FirebaseEventManager.shared
        
        // Call super with empty values and the dummy event manager
        super.init(eventId: spaceId, date: Date(), eventManager: dummyEventManager)
        
        // Start our custom listening logic
        Task {
            await startSpacesListening(spaceId: spaceId)
        }
    }
    
    // MARK: - Overridden Properties and Methods
    
    // Override the messages getter to use our shadow property instead
    override var messages: [ChatMessage] {
        return spacesMessages
    }
    
    // Override sendMessage to use spaces-specific implementation
    override func sendMessage(text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // --- REMOVED: The logic that generated its own UUID ---
        /*
         var senderId = currentUserId
         if senderId.isEmpty { ... }
         let senderName = currentUsername
        */

        // +++ ADDED: Get the user identity reliably from the AppModel +++
        let user = appModel.currentUser
        
        // Add checks to make sure user identity is valid before sending
        guard !user.id.isEmpty, !user.name.isEmpty else {
            print("❌ Cannot send message. User ID or Username is missing from AppModel.")
            return
        }
        
        print("SpacesChatViewModel.sendMessage -> senderId: \(user.id), senderName: \(user.name)")
        
        // Send the message through the spaces manager using the correct user data
        spacesManager.sendMessage(
            trimmedText,
            senderId: user.id,
            senderName: user.name,
            spaceId: eventId // Using eventId from parent class to store spaceId
        )
    }
    
    // Override opacity methods to use spaces manager
    override func getOpacity(for id: String) async -> Double {
        return spacesManager.getMessageOpacity(for: id)
    }
    
    override func updateMessageOpacity(id: String, opacity: Double) async {
        spacesManager.updateMessageOpacity(id: id, opacity: opacity)
    }
    
    // MARK: - Private Methods
    
    // Custom listening method for spaces
    private func startSpacesListening(spaceId: String) async {
        print("Starting spaces chat listener for space ID: \(spaceId)")
        
        // Start the spaces manager listener
        spacesManager.startListening(spaceId: spaceId)
        
        // Keep updating messages from spaces manager
        updateTask = Task {
            while !Task.isCancelled {
                // Get messages from the spaces manager
                let newMessages = spacesManager.messages
                
                // Update our shadow property
                if self.spacesMessages != newMessages {
                    self.spacesMessages = newMessages
                    
                    // Manually trigger objectWillChange to notify observers
                    self.objectWillChange.send()
                }
                
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
    
    // MARK: - Cleanup
    
    // Method to clean up resources
    func cleanup() {
        // Cancel update task
        updateTask?.cancel()
        updateTask = nil
        
        // Stop listener in SpacesChatManager
        Task {
            await spacesManager.stopListening()
        }
    }
    
    // MARK: - Deinitializer
    
    deinit {
        // Cancel update task
        updateTask?.cancel()
        print("SpacesChatViewModel deinit")
    }
}
