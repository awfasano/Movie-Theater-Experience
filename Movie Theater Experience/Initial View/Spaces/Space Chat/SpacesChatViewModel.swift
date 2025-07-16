import SwiftUI
import FirebaseFirestore
import Combine

@MainActor
class SpacesChatViewModel: ChatViewModel {
    // MARK: - Properties
    
    private let spacesManager = SpacesChatManager.shared
    private var updateTask: Task<Void, Never>?
    private let appModel = AppModel.shared
    
    // Shadow storage for messages
    private var spacesMessages: [ChatMessage] = []
    
    // Combine publishers for efficient updates
    private var cancellables = Set<AnyCancellable>()
    private let messageUpdateSubject = PassthroughSubject<[ChatMessage], Never>()
    
    // Throttle updates to prevent excessive redraws
    private let updateThrottle: TimeInterval = 0.3
    private var lastUpdateTime: Date = .distantPast
    
    // MARK: - Initialization
    
    init(spaceId: String) {
        // Create a dummy FirebaseEventManager that won't be used
        let dummyEventManager = FirebaseEventManager.shared
        
        // Call super with empty values and the dummy event manager
        super.init(eventId: spaceId, date: Date(), eventManager: dummyEventManager)
        
        // Set up efficient message updates
        setupMessageUpdates()
        
        // Start listening after a brief delay to prevent initial stuttering
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            await startSpacesListening(spaceId: spaceId)
        }
    }
    
    // MARK: - Setup
    
    private func setupMessageUpdates() {
        // Throttle message updates to prevent excessive redraws
        messageUpdateSubject
            .throttle(for: .milliseconds(300), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] newMessages in
                guard let self = self else { return }
                
                // Only update if messages actually changed
                if self.spacesMessages != newMessages {
                    self.spacesMessages = newMessages
                    self.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Overridden Properties and Methods
    
    override var messages: [ChatMessage] {
        return spacesMessages
    }
    
    override func sendMessage(text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        let user = appModel.currentUser
        
        // Validate user identity
        guard !user.id.isEmpty, !user.name.isEmpty else {
            print("❌ Cannot send message. User ID or Username is missing from AppModel.")
            return
        }
        
        print("SpacesChatViewModel.sendMessage -> senderId: \(user.id), senderName: \(user.name)")
        
        // Send message asynchronously to prevent UI blocking
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            await self.spacesManager.sendMessage(
                trimmedText,
                senderId: user.id,
                senderName: user.name,
                spaceId: self.eventId
            )
        }
    }
    
    override func getOpacity(for id: String) async -> Double {
        return spacesManager.getMessageOpacity(for: id)
    }
    
    override func updateMessageOpacity(id: String, opacity: Double) async {
        spacesManager.updateMessageOpacity(id: id, opacity: opacity)
    }
    
    // MARK: - Private Methods
    
    private func startSpacesListening(spaceId: String) async {
        print("Starting spaces chat listener for space ID: \(spaceId)")
        
        // Start the spaces manager listener
        spacesManager.startListening(spaceId: spaceId)
        
        // Use a more efficient update mechanism
        updateTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Initial update
            let initialMessages = await spacesManager.getMessages()
            self.messageUpdateSubject.send(initialMessages)
            
            // Set up periodic updates with adaptive timing
            var consecutiveEmptyUpdates = 0
            var updateInterval: TimeInterval = 0.1
            
            while !Task.isCancelled {
                let newMessages = await spacesManager.getMessages()
                
                // Check if there are actual changes
                if self.spacesMessages != newMessages {
                    self.messageUpdateSubject.send(newMessages)
                    consecutiveEmptyUpdates = 0
                    updateInterval = 0.1 // Reset to fast updates when active
                } else {
                    consecutiveEmptyUpdates += 1
                    
                    // Gradually increase interval if no updates
                    if consecutiveEmptyUpdates > 10 {
                        updateInterval = min(updateInterval * 1.5, 1.0) // Cap at 1 second
                    }
                }
                
                try? await Task.sleep(for: .milliseconds(Int(updateInterval * 1000)))
            }
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        // Cancel all tasks and subscriptions
        updateTask?.cancel()
        updateTask = nil
        cancellables.removeAll()
        
        Task {
            await spacesManager.stopListening()
        }
    }
    
    deinit {
        updateTask?.cancel()
        cancellables.removeAll()
        print("SpacesChatViewModel deinit")
    }
}
