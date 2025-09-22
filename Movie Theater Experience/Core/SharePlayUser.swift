import Foundation

/// A lightweight representation of a user for SharePlay/session contexts.
/// Kept minimal to match current usage in AppModel.
public struct SharePlayUser: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
