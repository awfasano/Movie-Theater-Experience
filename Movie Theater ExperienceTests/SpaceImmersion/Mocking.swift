import Foundation
import RealityKit
@testable import Movie_Theater_Experience

final class MockSpaceFetcher: SpaceFetching {
    var result: Result<[SpaceData], Error> = .success([])
    var fetchCallCount = 0
    func fetchSpaces(completion: @escaping (Result<[SpaceData], Error>) -> Void) {
        fetchCallCount += 1
        completion(result)
    }
}

final class MockSpaceEntityLoader: SpaceEntityLoading {
    var result: Result<Entity, Error> = .failure(SpaceServiceError.loadingFailed)
    var loadCallCount = 0
    func loadSpaceEntity(from space: SpaceData) async throws -> Entity {
        loadCallCount += 1
        switch result {
        case .success(let entity):
            return entity
        case .failure(let error):
            throw error
        }
    }
}
