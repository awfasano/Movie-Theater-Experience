// Example of how to add the environment object
Button("Open Spaces") {
    openWindow(id: "spacesWindow")
}
.onAppear {
    // Create the shared instance if it doesn't exist
    if selectedSpace == nil {
        selectedSpace = SelectedSpace()
    }
} 