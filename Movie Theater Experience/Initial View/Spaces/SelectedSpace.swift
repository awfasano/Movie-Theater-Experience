//
//  SelectedSpace.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 4/6/25.
//

import Foundation

class SelectedSpace: ObservableObject {
    @Published var space: SpaceData?
    @Published var currentSeat: String?
}
