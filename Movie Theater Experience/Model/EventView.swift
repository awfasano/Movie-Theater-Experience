import SwiftUI

struct EventView: View {
    var event: CalendarEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.headline)
                .foregroundColor(.white)
            
            HStack {
                Text("From:")
                Text(event.date, style: .time)
                    .font(.caption)
            }
            
            HStack {
                Text("To:")
                Text(event.end, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(event.description)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(8)
        .background(Color.blue.opacity(0.7))
        .cornerRadius(8)
    }
}
