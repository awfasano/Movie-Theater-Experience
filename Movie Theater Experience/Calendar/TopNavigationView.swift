//
//  TopNavigationView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/31/25.
//

import Foundation
import SwiftUI

struct TopNavigationView: View {
    @Binding var currentDate: Date
    @Binding var isRefreshing: Bool
    
    let onRefresh: () -> Void
    let onMonthScroll: (Int) -> Void
    
    var body: some View {
        HStack {
            // Month Navigation
            Button { onMonthScroll(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .center, spacing: 4) {
                Text(currentDate.monthAndYear)
                    .font(.title2).bold()
                Text(currentDate.formatted(.dateTime.weekday(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Button { onMonthScroll(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            Spacer()
            
            // Refresh Button
            Button { onRefresh() } label: {
                Image(systemName: isRefreshing
                      ? "arrow.triangle.2.circlepath.circle.fill"
                      : "arrow.triangle.2.circlepath.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .padding(8)
            }
        }
        .padding(.horizontal)
    }
}
