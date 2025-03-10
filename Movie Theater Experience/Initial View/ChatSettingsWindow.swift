//
//  ChatSettingsWindow.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/31/25.
//

import SwiftUI

struct ChatSettingsWindow: View {
    // Persist the username using AppStorage.
    @AppStorage("username") private var username: String = ""
    
    // Persist colors as hex strings.
    @AppStorage("sentMessageColorHex") private var sentMessageColorHex: String = "#0000FF"   // Default blue.
    @AppStorage("receivedMessageColorHex") private var receivedMessageColorHex: String = "#808080" // Default gray.
    
    // Create Bindings to convert hex strings to Color and vice versa.
    private var sentMessageColorBinding: Binding<Color> {
        Binding<Color>(
            get: {
                Color(hex: sentMessageColorHex) ?? .blue
            },
            set: { newColor in
                if let hex = newColor.toHex {
                    sentMessageColorHex = hex
                }
            }
        )
    }
    
    private var receivedMessageColorBinding: Binding<Color> {
        Binding<Color>(
            get: {
                Color(hex: receivedMessageColorHex) ?? .gray
            },
            set: { newColor in
                if let hex = newColor.toHex {
                    receivedMessageColorHex = hex
                }
            }
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // MARK: - Left Side: Settings Form (1/3 of available width)
                Form {
                    // Username Section
                    Section(header: Text("Username")) {
                        TextField("Enter your username", text: $username)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                    }
                    
                    // Sent Message Color Section
                    Section(header: Text("Sent Message Color")) {
                        ColorPicker("Select your message color", selection: sentMessageColorBinding)
                            .padding(.vertical, 5)
                    }
                    
                    // Received Message Color Section
                    Section(header: Text("Received Message Color")) {
                        ColorPicker("Select received message color", selection: receivedMessageColorBinding)
                            .padding(.vertical, 5)
                    }
                }
                .frame(width: geometry.size.width * 0.33)
                .padding([.top, .leading, .bottom])
                
                Divider()
                
                // MARK: - Right Side: Information Text (2/3 of available width)
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        Group {
                            Text("Get on Our Schedule")
                                .font(.headline)
                            
                            Text("If you would like to get on our schedule to play your movie, please email us at:")
                            
                            Text("anthony@spaces.com")
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            
                            Text("Also, if you have found bugs or have suggestions for improvements, please don't hesitate to reach out.")
                        }
                        
                        Divider()
                        
                        Group {
                            Text("Support the Project")
                                .font(.headline)
                                .padding(.top, 10)
                            
                            Text("If you want to buy me coffee or support this project, I am looking to add features in the future as well as create better spaces for content. You can send money to:")
                            
                            Text("anthony@spaces.com")
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            
                            Text("Better spaces, streaming videos, and databases all cost money, so if you would like to support the project, I would really appreciate it.")
                        }
                        
                        Divider()
                        
                        Group {
                            Text("Terms of Use & Privacy Policy")
                                .font(.headline)
                                .padding(.top, 10)
                            
                            Text("Additionally, here are our Terms of Use and Privacy Policy if you would like to take a look:")
                            
                            // Replace "link" with an actual URL link if needed.
                            Text("link")
                                .foregroundColor(.blue)
                                .underline()
                        }
                        
                        Spacer() // Push content to the top.
                    }
                    .padding([.top, .bottom])
                    .padding(.trailing, 50) // Extra right padding to keep text from running off the side.
                    .padding(.leading, 10)  // Optional: slight left padding inside the right section.
                }
                .frame(width: geometry.size.width * 0.67)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
}

struct ChatSettingsWindow_Previews: PreviewProvider {
    static var previews: some View {
        ChatSettingsWindow()
    }
}
