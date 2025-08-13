import SwiftUI

struct ChatSettingsWindow: View {
    // 1. Get a reference to the AppModel from the environment
    @Environment(AppModel.self) private var appModel

    // Persist the username using AppStorage.
    @AppStorage("username") private var username: String = ""
    
    // Persist colors as hex strings.
    @AppStorage("sentMessageColorHex") private var sentMessageColorHex: String = "#0000FF"  // Default blue.
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
                // 2. Sync the username to the AppModel whenever it changes
                .onChange(of: username) { _, newUsername in
                    appModel.username = newUsername
                    print("🔄 [ChatSettingsWindow] Synced AppModel username to: \(newUsername)")
                }
                
                Divider()
                
                // MARK: - Right Side: Information Text (2/3 of available width)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // --- UPDATED TEXT BEGINS HERE ---
                        
                        Group {
                            Text("The Future of Spiera & Your Feedback")
                                .font(.headline)
                            
                            Text("We have major updates and exciting new features planned for the coming patches. Our goal is to create a rich, well-rounded application for you to enjoy. Your feedback is crucial to this process, and we'd love to hear your ideas and suggestions!")
                        }
                        
                        Divider()
                        
                        Group {
                            Text("Create with Us")
                                .font(.headline)
                            
                            Text("Do you have an idea for an immersive story using video and audio? Or perhaps a 3D space you'd like to feature? We are always looking for collaborators. Please reach out to discuss how we can incorporate your content.")
                        }
                        
                        Divider()

                        // This new section combines contact, collaboration, and support info.
                        Group {
                            Text("Contact, Collaboration & Support")
                                .font(.headline)
                            
                            Text("For all inquiries, or if you'd like to support the project, please use the details below. Contributions help cover server costs and future development, and are greatly appreciated!")
                            
                            // Contact details VStack for clean alignment
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Email: spiera.anthony@gmail.com")
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                    .textSelection(.enabled) // Makes it easy to copy

                                Text("Venmo: @awfasano")
                                    .fontWeight(.bold)
                                    .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.86)) // Venmo blue
                                    .textSelection(.enabled)
                            }
                            .padding(.top, 5)
                        }
                        
                        Divider()
                        
                        Group {
                            Text("Terms of Use & Privacy Policy")
                                .font(.headline)
                            
                            Text("For more details on how we operate and handle your data, please review our policies on our website:")
                            
                            if let url = URL(string: "https://spindleworlds.web.app/") {
                                Link("spindleworlds.web.app", destination: url)
                            }
                        }
                        
                        // --- UPDATED TEXT ENDS HERE ---

                        Spacer() // Push content to the top.
                    }
                    .padding([.top, .bottom])
                    .padding(.trailing, 40)
                    .padding(.leading, 20)
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
            .environment(AppModel.shared)
    }
}
