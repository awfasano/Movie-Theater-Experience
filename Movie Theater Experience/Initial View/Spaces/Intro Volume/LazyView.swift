//
//  LazyView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 2/5/25.
//

import Foundation
import SwiftUI

struct LazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @escaping () -> Content) {
        self.build = build
    }
    var body: Content {
        build()
    }
}
