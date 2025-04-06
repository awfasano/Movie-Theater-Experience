import SwiftUI
import RealityKit

// Enhanced modifier for a true floating sphere effect
struct FloatingSphereModifier: ViewModifier {
    @State private var isHovering = false
    @State private var floatOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    let isAvailable: Bool
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        content
            // Scale effect when hovering
            .scaleEffect(isHovering && isAvailable ? 1.15 : 1.0)
            // Glow effect
            .shadow(
                color: isSelected ? .green.opacity(0.8) :
                      (isHovering && isAvailable ? .yellow.opacity(0.7) : .black.opacity(0.4)),
                radius: isSelected ? 15 :
                       (isHovering && isAvailable ? 12 : 6),
                x: 0,
                y: isHovering && isAvailable ? 0 : 4
            )
            // Ambient light shadow for 3D effect
            .background(
                Circle()
                    .fill(Color.black.opacity(0.2))
                    .blur(radius: 8)
                    .offset(y: 10)
                    .scaleEffect(0.9)
            )
            // Continuous floating animation
            .offset(y: floatOffset)
            // Subtle rotation for a more dynamic effect
            .rotationEffect(Angle(degrees: rotationAngle))
            .onAppear {
                // Create a continuous floating animation
                withAnimation(
                    Animation.easeInOut(duration: 3.0)
                        .repeatForever(autoreverses: true)
                ) {
                    floatOffset = -4.0
                }
                
                // Add subtle rotation animation
                withAnimation(
                    Animation.linear(duration: 8.0)
                        .repeatForever(autoreverses: false)
                ) {
                    rotationAngle = 5.0
                }
            }
            // Smooth transition for hover effects
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

// Custom button style for seat selection in the bottom scroll view
struct SeatButtonStyle: ButtonStyle {
    var isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3) // Slightly larger text
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.green.opacity(0.2) : Color.secondary.opacity(0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct SpaceMapView: View {
    @EnvironmentObject var selectedSpace: SelectedSpace
    @State private var currentSeat: String = ""
    @State private var availableSeats: [SeatPosition] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    // Get current user ID
    private let userId = UUID().uuidString
    
    // Fixed dimensions for the view
    private let viewWidth: CGFloat = 1024
    private let viewHeight: CGFloat = 1024
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading seat map...")
                    .onAppear {
                        print("LOADING VIEW APPEARED - SelectedSpace: \(selectedSpace.space?.spaceName ?? "nil")")
                        
                        // Simulate loading delay and then set isLoading to false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            print("LOADING TIMER COMPLETED")
                            if selectedSpace.space == nil {
                                print("ERROR: No space selected")
                                errorMessage = "No space selected"
                            } else {
                                print("SPACE FOUND: \(selectedSpace.space?.spaceName ?? "unnamed")")
                            }
                            isLoading = false
                        }
                    }
            } else if let error = errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .padding()
                    Button("Try Again") {
                        print("TRY AGAIN BUTTON PRESSED")
                        errorMessage = nil
                        isLoading = true
                    }
                }
            } else if let space = selectedSpace.space, let seats = space.seats, !seats.isEmpty {
                renderMap(space: space, seats: seats)
                    .onAppear {
                        print("ENTERING RENDER MAP - Space: \(space.spaceName ?? "unnamed"), Seats count: \(seats.count)")
                    }
            } else {
                VStack {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No seat map available for this space")
                        .padding()
                    if selectedSpace.space == nil {
                        Text("Please select a space first")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if selectedSpace.space?.seats == nil || selectedSpace.space?.seats?.isEmpty == true {
                        Text("This space has no seats configured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            print("VIEW APPEARED - Resetting loading state")
            isLoading = true
        }
        .onChange(of: selectedSpace.space?.id) { newValue in
            print("SELECTED SPACE CHANGED - New ID: \(newValue ?? "nil")")
            isLoading = true
            errorMessage = nil
        }
    }
    
    private func renderMap(space: SpaceData, seats: [SeatPosition]) -> some View {
        print("RENDER MAP FUNCTION CALLED")
        
        // Get the current seat label
        let currentSeatLabel = seats.first(where: { $0.id == currentSeat })?.label ?? ""
        
        return VStack(spacing: 12) {
            // Fixed-size map area with floating spheres
            ZStack {
                // Background map (with no grid lines)
                if let mapURL = space.mapURL {
                    AsyncImage(url: URL(string: mapURL)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: viewWidth, height: viewHeight)
                                .clipped()
                        case .failure:
                            Rectangle()
                                .fill(Color.indigo.opacity(0.2))
                                .frame(width: viewWidth, height: viewHeight)
                                .overlay(
                                    Text("Failed to load map image")
                                        .foregroundColor(.secondary)
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    // Simple gradient background
                    LinearGradient(
                        gradient: Gradient(colors: [Color.indigo.opacity(0.2), Color.purple.opacity(0.2)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: viewWidth, height: viewHeight)
                }
                
                // Floating spheres for each seat
                ZStack {
                    ForEach(seats) { seat in
                        Button(action: {
                            if seat.isAvailable || seat.id == currentSeat {
                                selectSeat(seatId: seat.id)
                            }
                        }) {
                            createFloatingSphere(
                                isSelected: currentSeat == seat.id,
                                isAvailable: seat.isAvailable
                            )
                        }
                        .buttonStyle(PlainButtonStyle()) // Remove default button styling
                        .disabled(!seat.isAvailable && seat.id != currentSeat)
                        .opacity(seat.isAvailable || seat.id == currentSeat ? 1.0 : 0.5)
                        .modifier(FloatingSphereModifier(
                            isAvailable: seat.isAvailable,
                            isSelected: currentSeat == seat.id
                        ))
                        .position(seat.position)
                    }
                }
                .frame(width: viewWidth, height: viewHeight)
            }
            .frame(width: viewWidth, height: viewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 5)
            
            // Updated current position info with a larger font
            if !currentSeat.isEmpty {
                Text("Current seat: \(currentSeatLabel)")
                    .font(.title2)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                    )
            }
            
            // Bottom section with seat buttons in a horizontal scroll view
            VStack(alignment: .leading, spacing: 12) {
                Text("Select a seat:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seats) { seat in
                            Button(action: {
                                if seat.isAvailable || seat.id == currentSeat {
                                    selectSeat(seatId: seat.id)
                                }
                            }) {
                                HStack {
                                    if let label = seat.label {
                                        Text("Seat \(label)")
                                            .fontWeight(currentSeat == seat.id ? .bold : .regular)
                                    } else {
                                        Text(seat.id)
                                            .fontWeight(currentSeat == seat.id ? .bold : .regular)
                                    }
                                    
                                    if currentSeat == seat.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .buttonStyle(SeatButtonStyle(isSelected: currentSeat == seat.id))
                            .disabled(!seat.isAvailable && seat.id != currentSeat)
                            .opacity(seat.isAvailable || seat.id == currentSeat ? 1.0 : 0.5)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: viewWidth)
                .padding(.bottom, 8)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .frame(width: viewWidth)
        }
    }
    
    // Function to create a floating sphere visual component
    private func createFloatingSphere(isSelected: Bool, isAvailable: Bool) -> some View {
        ZStack {
            // Main sphere with glass-like effect
            Circle()
                .fill(
                    isSelected ?
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green.opacity(0.9), Color.green.opacity(0.5)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        isAvailable ?
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.5)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                gradient: Gradient(colors: [Color.gray.opacity(0.7), Color.gray.opacity(0.3)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                )
                .frame(width: 40, height: 40)
            
            // Inner glow
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            isSelected ? Color.green.opacity(0.8) :
                                        (isAvailable ? Color.white.opacity(0.8) : Color.white.opacity(0.4)),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 1,
                        endRadius: 20
                    )
                )
                .frame(width: 36, height: 36)
            
            // Light reflection highlight for 3D sphere effect
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 16, height: 16)
                .offset(x: -6, y: -6)
                .blur(radius: 2)
            
            // Bottom highlight (subtle)
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 12, height: 12)
                .offset(x: 6, y: 6)
                .blur(radius: 2)
            
            // Outer glow for selected or hovered seats
            if isSelected {
                Circle()
                    .fill(Color.green.opacity(0.4))
                    .frame(width: 50, height: 50)
                    .blur(radius: 10)
            }
        }
        .drawingGroup() // Optimize rendering performance
    }
    
    private func selectSeat(seatId: String) {
        print("SELECT SEAT FUNCTION CALLED - Seat ID: \(seatId)")
        
        guard seatId != currentSeat else {
            print("SEAT ALREADY SELECTED - No change")
            return
        }
        
        currentSeat = seatId
        print("✅ SEAT SELECTED: \(seatId)")
    }
}

#Preview {
    SpaceMapView()
        .environmentObject(SelectedSpace())
}
