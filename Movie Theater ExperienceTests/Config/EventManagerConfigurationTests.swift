import XCTest
import FirebaseFirestore
@testable import Movie_Theater_Experience

final class EventManagerConfigurationTests: XCTestCase {
    func testPathSegmentsIncludeRootDateAndEvent() {
        let config = EventManagerConfiguration(rootCollection: "Public Rooms")
        let date = Date(timeIntervalSince1970: 0)
        let segments = config.pathSegments(for: "event123", date: date)
        XCTAssertEqual(segments, ["Public Rooms", "01-01-1970", "Events", "event123", "messages"])
    }
    
    func testCollectionReferenceUsesRootCollection() {
        let config = EventManagerConfiguration(rootCollection: "Spaces")
        let db = Firestore.firestore()
        let ref = config.collectionReference(db: db, eventId: "abc", date: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(ref.path.contains("Spaces"))
    }
}
