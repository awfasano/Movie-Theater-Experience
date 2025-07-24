import Foundation
import SwiftUI

struct ChatSettingsNavBar: View {
    @AppStorage("username") private var username: String = ""
    @AppStorage("sentMessageColorHex") private var sentMessageColorHex: String = "#0000FF"
    @AppStorage("receivedMessageColorHex") private var receivedMessageColorHex: String = "#808080"
    
    private var sentMessageColorBinding: Binding<Color> {
        Binding<Color>(
            get: { Color(hex: sentMessageColorHex) ?? .blue },
            set: { newColor in
                if let hex = newColor.toHex {
                    sentMessageColorHex = hex
                }
            }
        )
    }
    
    private var receivedMessageColorBinding: Binding<Color> {
        Binding<Color>(
            get: { Color(hex: receivedMessageColorHex) ?? .gray },
            set: { newColor in
                if let hex = newColor.toHex {
                    receivedMessageColorHex = hex
                }
            }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Username Section
            /*
            VStack(alignment: .leading, spacing: 8) {
                Label("Username", systemImage: "person.circle.fill")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                TextField("Enter username", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
            }
            */
            
            // Message Colors Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Message Colors")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 20) {
                    // Sent Messages Color
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Sent", systemImage: "arrow.up.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(sentMessageColorBinding.wrappedValue)
                                .frame(width: 24, height: 24)
                            
                            ColorPicker("", selection: sentMessageColorBinding)
                                .labelsHidden()
                                .frame(width: 44, height: 44)
                        }
                    }
                    
                    // Received Messages Color
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Received", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(receivedMessageColorBinding.wrappedValue)
                                .frame(width: 24, height: 24)
                            
                            ColorPicker("", selection: receivedMessageColorBinding)
                                .labelsHidden()
                                .frame(width: 44, height: 44)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(40)
        .background(Color(.systemBackground))
        .cornerRadius(5)
        .shadow(radius: 2)
    }
}

struct ChatSettingsNavBar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ChatSettingsNavBar()
                .previewLayout(.sizeThatFits)
                .padding()
            
            ChatSettingsNavBar()
                .previewLayout(.sizeThatFits)
                .padding()
                .preferredColorScheme(.dark)
        }
    }
}
