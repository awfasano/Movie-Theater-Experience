import SwiftUI
import FirebaseFirestore

// This extends your existing ChatViewModel to handle spaces data
@MainActor
class SpacesChatViewModel: ChatViewModel {
    // MARK: - Properties
    
    // The spaces manager to handle Firebase operations for spaces
    private let spacesManager = SpacesChatManager.shared
    private var updateTask: Task<Void, Never>?
    
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
        
        // Get the current user ID and name
        var senderId = currentUserId
        if senderId.isEmpty {
            senderId = UUID().uuidString
            currentUserId = senderId
            print("Generated new userId for spaces: \(senderId)")
        } else {
            print("Using existing userId for spaces: \(senderId)")
        }
        
        let senderName = currentUsername
        print("SpacesChatViewModel.sendMessage -> senderId: \(senderId), senderName: \(senderName)")
        
        // Send the message through the spaces manager
        spacesManager.sendMessage(
            trimmedText,
            senderId: senderId,
            senderName: senderName,
            spaceId: eventId // Using eventId from parent class to store spaceId
        )
    }
    
    // Override opacity methods to use spaces manager
    override func getOpacity(for id: String) async -> Double {
        return await spacesManager.getMessageOpacity(for: id)
    }
    
    override func updateMessageOpacity(id: String, opacity: Double) async {
        await spacesManager.updateMessageOpacity(id: id, opacity: opacity)
    }
    
    // MARK: - Private Methods
    
    // Custom listening method for spaces
    private func startSpacesListening(spaceId: String) async {
        // Guard against duplicate listeners
        guard updateTask == nil else { return }

        print("Starting spaces chat listener for space ID: \(spaceId)")

        // Start the spaces manager listener
        await spacesManager.startListening(spaceId: spaceId)
        
        // Keep updating messages from spaces manager
        updateTask = Task {
            while !Task.isCancelled {
                // Get messages from the spaces manager
                let newMessages = await spacesManager.messages
                
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
        updateTask = nil
        // Stop the Firestore listener to prevent leaks.
        // Note: spacesManager.stopListening() is @MainActor, so we dispatch it.
        Task { @MainActor [spacesManager] in
            spacesManager.stopListening()
        }
        print("SpacesChatViewModel deinit")
    }
}
