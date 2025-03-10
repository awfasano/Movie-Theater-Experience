//
//  VolumetricSpaceModel.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/2/25.
//

import Foundation
import RealityKit
import Combine

class VolumetricSpaceViewModel: ObservableObject {
    @Published var entity: Entity?
    @Published var isLoading = false
    @Published var error: Error?
    
    private let service = SpaceService()
    private var cancellables = Set<AnyCancellable>()
    
    func loadSpace(_ space: SpaceData) {
        isLoading = true
        error = nil
        entity = nil
        
        service.loadSpace(from: space)
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                self.isLoading = false
                
                if case .failure(let error) = completion {
                    self.error = error
                }
            }, receiveValue: { [weak self] entity in
                self?.entity = entity
            })
            .store(in: &cancellables)
    }
}
