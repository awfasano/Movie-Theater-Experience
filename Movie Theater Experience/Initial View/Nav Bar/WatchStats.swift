//
//  WatchStats.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/22/25.
//

import Foundation

struct WatchStats: Codable, Hashable {
    let watchTime: TimeInterval
    let viewerCount: Int
}
