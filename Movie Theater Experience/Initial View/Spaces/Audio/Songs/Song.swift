import Foundation
import FirebaseFirestore

struct Song: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var song: String
    var artist: String
    var artworkURL: String
    var audioURL: String
    var uploadedAt: Date?
}
