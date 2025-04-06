//
//  DaySelectionView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/31/25.
//

import Foundation
import SwiftUI
import RealityKit

struct DaySelectionView: View {
    @Binding var currentDate: Date
    @Binding var scrollToToday: Bool
    let onDateChange: (Date) -> Void
    
    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(currentDate.startOfMonth.daysInMonth(), id: \.self) { day in
                        VStack(spacing: 8) {
                            Text(day.weekdaySymbol)
                                .font(.body)
                                .foregroundStyle(.secondary)
                            
                            Text("\(day.day)")
                                .font(.extraLargeTitle2)
                                .bold()
                                .foregroundColor(textColor(for: day))
                                .padding(20)
                                .background(
                                    ZStack {
                                        if isToday(day) && isSelected(day) {
                                            Circle()
                                                .fill(Color.red)
                                                .shadow(color: .red.opacity(0.3), radius: 4)
                                        } else if isSelected(day) {
                                            Circle()
                                                .fill(.thinMaterial)
                                        }
                                    }
                                )
                        }
                        .onTapGesture {
                            withAnimation(.spring()) {
                                onDateChange(day)
                                scrollProxy.scrollTo(day, anchor: .center)
                            }
                        }
                        .frame(minWidth: 80)
                        .id(day)
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: scrollToToday) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        let today = Calendar.current.startOfDay(for: Date())
                        scrollProxy.scrollTo(today, anchor: .center)
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    let today = Calendar.current.startOfDay(for: Date())
                    scrollProxy.scrollTo(today, anchor: .center)
                    
                    if !Calendar.current.isDate(currentDate, inSameDayAs: today) {
                        onDateChange(today)
                    }
                }
            }
        }
    }
    
    private func isToday(_ day: Date) -> Bool {
        Calendar.current.isDateInToday(day)
    }
    
    private func isSelected(_ day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: currentDate)
    }
    
    private func textColor(for day: Date) -> Color {
        if isToday(day) {
            return isSelected(day) ? .white : .red
        } else if isSelected(day) {
            return .primary
        } else {
            return .primary
        }
    }
}
