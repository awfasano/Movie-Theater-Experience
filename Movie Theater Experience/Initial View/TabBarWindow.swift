//
//  TabBarWindow.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/14/25.
//

import Foundation
import SwiftUI

struct TabBarWindow: View {
    @State private var selectedTab: Int = 0
    @StateObject private var calendarService = CalendarService()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // CalendarView Tab
            CalendarView(calendarService: calendarService)
                .tabItem {
                    Label("Current Showings", systemImage: "calendar")
                }
                .tag(0)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            // Chat Settings Tab
            ChatSettingsWindow()
                .tabItem {
                    Label("Chat Settings", systemImage: "gear")
                }
                .tag(1)
        }
        .onAppear {
            calendarService.fetchAllEvents()
        }
    }
}
