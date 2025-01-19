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
            CalendarView(events: calendarService.events)
                .tabItem {
                    Label("Current Showings", systemImage: "1.circle")
                }
                .tag(0)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            // Private Showing Tab
            Text("Private Showing")
                .tabItem {
                    Label("Private Showing", systemImage: "2.circle")
                }
                .tag(1)
            
            // Settings Tab
            Text("Settings")
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(2)
        }
        .onAppear {
            calendarService.fetchAllEvents()
        }
    }
}
