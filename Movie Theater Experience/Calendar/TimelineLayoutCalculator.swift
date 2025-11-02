import SwiftUI

struct TimelineLayoutResult {
    let positionedEvents: [PositionedEvent]
    let maxRow: Int
}

struct TimelineLayoutCalculator {
    let hourWidth: CGFloat
    
    func layout(events: [CalendarEvent], on date: Date) -> TimelineLayoutResult {
        var positioned: [PositionedEvent] = []
        var rows: [[CalendarEvent]] = []
        var localMaxRow = 0
        
        let dayEvents = events.filter {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }
        
        for event in dayEvents.sorted(by: { $0.date < $1.date }) {
            let startHour = hourValue(for: event.date)
            let endHour = hourValue(for: event.end)
            let eventWidth = max((endHour - startHour) * hourWidth, hourWidth / 2)
            let xPosition = startHour * hourWidth
            
            var placed = false
            for (index, row) in rows.enumerated() {
                if !row.contains(where: { overlapping($0, event) }) {
                    rows[index].append(event)
                    positioned.append(PositionedEvent(
                        event: event,
                        row: index,
                        xPosition: xPosition,
                        width: eventWidth
                    ))
                    placed = true
                    break
                }
            }
            
            if !placed {
                rows.append([event])
                let rowIndex = rows.count - 1
                positioned.append(PositionedEvent(
                    event: event,
                    row: rowIndex,
                    xPosition: xPosition,
                    width: eventWidth
                ))
                localMaxRow = max(localMaxRow, rowIndex)
            }
        }
        
        return TimelineLayoutResult(positionedEvents: positioned, maxRow: localMaxRow)
    }
    
    func hourValue(for date: Date) -> CGFloat {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hr = CGFloat(comps.hour ?? 0)
        let min = CGFloat(comps.minute ?? 0)
        return hr + min / 60
    }
    
    func overlapping(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        max(a.date, b.date) < min(a.end, b.end)
    }
}
