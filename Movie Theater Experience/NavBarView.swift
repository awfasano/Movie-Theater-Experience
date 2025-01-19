import SwiftUI

struct NavBarView: View {
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
        
   
   @AppStorage("showEmojis") private var showEmojis = true
   @State private var showMovieEndAlert = false
   
    let videoSyncService = VideoSyncService.shared
    
   var body: some View {
       HStack(spacing: 40) {
           // Chat Button
           Button(action: {
               openWindow(id: "chatWindow")
           }) {
               Image(systemName: "message.fill")
                   .resizable()
                   .frame(width: 30, height: 30)
           }
           
           // Emoji Button
           Button(action: {
               openWindow(id: "emojiWindow")
           }) {
               Image(systemName: "face.smiling.fill")
                   .resizable()
                   .frame(width: 30, height: 30)
           }
           
           // Toggle Emoji Visibility Button
           Button(action: {
               showEmojis.toggle()
               TheatreEntityWrapper.shared.setEmojiVisibility(showEmojis)
           }) {
               Image(systemName: showEmojis ? "eye.fill" : "eye.slash.fill")
                   .resizable()
                   .frame(width: 30, height: 30)
                   .overlay(
                    Image(systemName: "face.smiling.fill")
                        .resizable()
                        .frame(width: 15, height: 15)
                        .offset(x: 8, y: 8)
                   )
           }
           
           // Movie Button
           Button(action: {
               if let videoURL = appModel.selectedVideoURL {
                   appModel.selectedVideoURL = videoURL
                   appModel.isMovieWindowOpen = true
                   openWindow(id: "movieWindow")
               }
           }) {
               Image(systemName: "rectangle.on.rectangle")
                   .resizable()
                   .frame(width: 30, height: 30)
           }
           .disabled(appModel.selectedVideoURL == nil)
           
           // Seat Map Button
           Button(action: {
               openWindow(id: "seatMap")
           }) {
               Image(systemName: "chair.fill")
                   .resizable()
                   .frame(width: 30, height: 30)
           }
           
           // Toggle Immersive Space Button
           Button {
               Task { @MainActor in
                   switch appModel.immersiveSpaceState {
                   case .open:
                       appModel.immersiveSpaceState = .inTransition
                       await dismissImmersiveSpace()
                       if !appModel.isMovieWindowOpen, let _ = appModel.selectedVideoURL {
                           appModel.isMovieWindowOpen = true
                           openWindow(id: "movieWindow")
                       }
                   case .closed:
                       appModel.immersiveSpaceState = .inTransition
                       switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                       case .opened:
                           break
                       case .userCancelled, .error:
                           fallthrough
                       @unknown default:
                           appModel.immersiveSpaceState = .closed
                       }
                   case .inTransition:
                       break
                   }
               }
           } label: {
               Image(systemName: appModel.immersiveSpaceState == .open ?
                     "person.slash.and.rectangles.filled" : "rectangle.inset.filled.and.person.filled")
               .resizable()
               .frame(width: 30, height: 30)
           }
           .disabled(appModel.immersiveSpaceState == .inTransition)
           
           // Exit Everything Button
           Button {
               Task { @MainActor in
                   // First handle video sync cleanup
                   videoSyncService.handleUserExit()
                   
                   // Then dismiss immersive space if open
                   if appModel.immersiveSpaceState == .open {
                       appModel.handleImmersiveSpaceTransition(to: .inTransition)
                       await dismissImmersiveSpace()
                   }
                   
                   // Reset app state
                   appModel.isMovieWindowOpen = false
                   appModel.selectedVideoURL = nil
                   appModel.currentEvent = nil
                   
                   // Dismiss all windows in sequence
                   dismissWindow(id: "chatWindow")
                   try? await Task.sleep(for: .milliseconds(100))
                   dismissWindow(id: "emojiWindow")
                   try? await Task.sleep(for: .milliseconds(100))
                   dismissWindow(id: "movieWindow")
                   try? await Task.sleep(for: .milliseconds(100))
                   dismissWindow(id: "seatMap")
                   try? await Task.sleep(for: .milliseconds(100))
                   dismissWindow(id: "navBar")
                   try? await Task.sleep(for: .milliseconds(200))
                   
                   // Finally open the tab bar window
                   openWindow(id: "tabBar")
               }
           } label: {
               Image(systemName: "xmark.circle.fill")
                   .resizable()
                   .frame(width: 30, height: 30)
                   .foregroundStyle(.red)
           }
       }
       .padding()
       .background(.ultraThinMaterial.opacity(0.9))
       .cornerRadius(10)
       .alert(isPresented: $showMovieEndAlert) {
           Alert(title: Text("Movie Ended"), message: Text("The movie has finished playing."), dismissButton: .default(Text("OK")))
       }
   }
}


