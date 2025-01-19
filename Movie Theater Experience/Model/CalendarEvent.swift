import Foundation
import SwiftUICore
import RealityKit
import FirebaseFirestore
import FirebaseFirestoreSwift

// The event model matching your Firebase structure
struct CalendarEvent: Identifiable, Codable {
    var id: String?
    let title: String
    let date: Date
    let end: Date
    let description: String
    let color: Int
    let videoURL: String
    
    // Regular initializer
    init(id: String? = nil, title: String, date: Date, end: Date, description: String, color: Int, videoURL: String) {
        self.id = id
        self.title = title
        self.date = date
        self.end = end
        self.description = description
        self.color = color
        self.videoURL = videoURL
    }
    
    // Computed property for color
    var eventColor: Color {
        switch color {
        case 1: return .red
        case 2: return .green
        case 3: return .blue
        case 4: return .purple
        case 5: return .orange
        case 6: return .yellow
        default: return .blue
        }
    }
    
    var videoURLObject: URL {
        URL(string: videoURL) ?? URL(string: "about:blank")!
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case end
        case description
        case color
        case videoURL
    }
    
    // Custom decoder for Firestore
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        color = try container.decode(Int.self, forKey: .color)
        videoURL = try container.decode(String.self, forKey: .videoURL)
        
        let dateTimestamp = try container.decode(Timestamp.self, forKey: .date)
        date = dateTimestamp.dateValue()
        
        let endTimestamp = try container.decode(Timestamp.self, forKey: .end)
        end = endTimestamp.dateValue()
    }
}

class CalendarService: ObservableObject {
    private let db = Firestore.firestore(database: "movieexperiencedb")
    @Published var events: [CalendarEvent] = []
    
    func fetchAllEvents() {
        // Reference to the Public Rooms collection
        let publicRoomsRef = db.collection("Public Rooms")
        
        // Get all date documents
        publicRoomsRef.getDocuments { [weak self] (snapshot, error) in
            if let error = error {
                print("Error getting date documents: \(error)")
                return
            }
            
            guard let dateDocuments = snapshot?.documents else { return }
            
            // For each date document, get its Events subcollection
            for dateDoc in dateDocuments {
                let eventsRef = dateDoc.reference.collection("Events")
                
                eventsRef.getDocuments { (eventSnapshot, eventError) in
                    if let eventError = eventError {
                        print("Error getting events for date \(dateDoc.documentID): \(eventError)")
                        return
                    }
                    guard let eventDocuments = eventSnapshot?.documents else { return }
                    
                    
                    // Parse each event document
                    let newEvents = eventDocuments.compactMap { eventDoc -> CalendarEvent? in
                        print("eventdoc.data()")
                        var tempCal = try? eventDoc.data(as: CalendarEvent.self)
                        tempCal?.id = eventDoc.documentID
                        print(tempCal)
                        return tempCal
                    }
                                        
                    // Update the events array on the main thread
                    DispatchQueue.main.async {
                        self?.events.append(contentsOf: newEvents)
                    }
                }
            }
        }
    }
    
    // Optional: Fetch events for a specific date
    func fetchEvents(forDate dateString: String) {
        let eventsRef = db.collection("Public Rooms").document(dateString).collection("Events")
        
        eventsRef.getDocuments { [weak self] (snapshot, error) in
            if let error = error {
                print("Error getting events: \(error)")
                return
            }
            
            guard let documents = snapshot?.documents else { return }
            
            let newEvents = documents.compactMap { document -> CalendarEvent? in
                try? document.data(as: CalendarEvent.self)
            }
            
            DispatchQueue.main.async {
                self?.events = newEvents
            }
        }
    }
}

// Helper extension for Color hex conversion
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}
