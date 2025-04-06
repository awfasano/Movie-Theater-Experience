import SwiftUI

// Create this file in the same module as your app file
struct VolumetricSpaceWrapper: View {
    let space: SpaceData
    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        // Create a local SelectedSpace instance
        let selectedSpace = SelectedSpace()
        selectedSpace.space = space
        
        return VolumetricSpaceView(space: space)
            .environment(appModel)
            .environmentObject(selectedSpace)
            // Other environment objects...
    }
} 