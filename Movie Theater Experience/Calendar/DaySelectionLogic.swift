import Foundation
import SwiftUI

enum DaySelectionTextStyle: Equatable {
    case todaySelected
    case today
    case selected
    case normal
    
    var color: Color {
        switch self {
        case .todaySelected:
            return .white
        case .today:
            return .red
        case .selected, .normal:
            return .primary
        }
    }
}

struct DaySelectionStyleCalculator {
    var calendar: Calendar = .current
    
    func isToday(_ day: Date) -> Bool {
        calendar.isDateInToday(day)
    }
    
    func isSelected(_ day: Date, comparedTo currentDate: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: currentDate)
    }
    
    func textStyle(for day: Date, currentDate: Date) -> DaySelectionTextStyle {
        if isToday(day) {
            return isSelected(day, comparedTo: currentDate) ? .todaySelected : .today
        } else if isSelected(day, comparedTo: currentDate) {
            return .selected
        } else {
            return .normal
        }
    }
}
