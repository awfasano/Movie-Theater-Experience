//
//  Movie_Theater_ExperienceApp.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/6/24.
//

import SwiftUI

@main
struct Movie_Theater_ExperienceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView()
        }.immersionStyle(selection: .constant(.full), in: .full)
    }
}
