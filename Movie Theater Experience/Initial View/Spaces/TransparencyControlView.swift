import SwiftUI

struct TransparencyControlView: View {
    // This correctly finds the shared AppModel.
    @Environment(AppModel.self) private var appModel

    var body: some View {
        // This is the key. Create a bindable reference to the appModel for the UI.
        @Bindable var appModel = appModel

        VStack(spacing: 15) {
            Text("Adjust Transparency")
                .font(.headline)
            
            // The slider now correctly binds to the bindable reference.
            Slider(
                value: $appModel.viewTransparency,
                in: 0...100,
                step: 1
            )
            
            Text("\(Int(appModel.viewTransparency))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .onChange(of: appModel.viewTransparency) { print("✅ Slider changed AppModel value to: \(appModel.viewTransparency)") }

        }
        .padding(20)
        .frame(width: 300)
    }
}
