//
//  QuickHostCommPanel.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/27/25.
//

import Foundation

//
//  QuickHostCommPanel.swift
//  Movie Theater Experience
//
//  Quick message broadcasting panel for hosts

import SwiftUI

struct QuickHostCommPanel: View {
    @EnvironmentObject private var hostAudioManager: HostAudioManager
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var customMessage = ""
    @State private var selectedMessageCategory: MessageCategory = .general
    @State private var isRecording = false
    @State private var recordingTime: Double = 0
    @State private var recordingTimer: Timer?
    
    enum MessageCategory: String, CaseIterable {
        case general = "General"
        case timing = "Timing"
        case scoring = "Scoring"
        case help = "Help"
        case celebration = "Celebration"
        
        var icon: String {
            switch self {
            case .general: return "megaphone.fill"
            case .timing: return "clock.fill"
            case .scoring: return "star.fill"
            case .help: return "questionmark.circle.fill"
            case .celebration: return "party.popper.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .general: return .blue
            case .timing: return .orange
            case .scoring: return .yellow
            case .help: return .purple
            case .celebration: return .green
            }
        }
    }
    
    private let predefinedMessages: [MessageCategory: [String]] = [
        .general: [
            "📢 Welcome everyone! Let's get started.",
            "🎯 Please pay attention for the next instruction.",
            "👥 Great teamwork so far, everyone!",
            "📱 Please check your screens for updates.",
            "🤫 Please keep the discussion at your tables only."
        ],
        .timing: [
            "⏰ You have 60 seconds to discuss.",
            "⚡ 30 seconds remaining!",
            "⏱️ 10 seconds left - time to decide!",
            "✋ Time's up! Please submit your answers.",
            "⏳ Taking a quick 2-minute break."
        ],
        .scoring: [
            "🎯 Let's see the correct answer...",
            "🏆 Congratulations to the winning table!",
            "📊 Here are the current scores.",
            "⭐ That was worth bonus points!",
            "🎲 This question is worth double points!"
        ],
        .help: [
            "❓ Does any table need clarification?",
            "🤔 Remember, you can discuss this with your team.",
            "💡 Here's a hint to help you out...",
            "🆘 If you're stuck, think about...",
            "👂 I'm here if any table needs help."
        ],
        .celebration: [
            "🎉 Excellent work, everyone!",
            "👏 That was a tough question - well done!",
            "🔥 You're all doing amazing!",
            "💪 Great thinking on that one!",
            "🌟 Perfect round, fantastic job!"
        ]
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    categorySelectionSection
                    predefinedMessagesSection
                    customMessageSection
                    voiceMessageSection
                    broadcastHistorySection
                }
                .padding()
            }
            .navigationTitle("Quick Messages")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Broadcast All") {
                        hostAudioManager.broadcastToAllRooms()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(hostAudioManager.activeRooms.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "megaphone.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Host Messages")
                        .font(.title3.bold())
                    
                    Text("Send instant messages to all tables")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Live indicator
                if hostAudioManager.isBroadcasting {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        
                        Text("LIVE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Stats bar
            HStack {
                Text("Active Tables: \(hostAudioManager.activeRooms.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Total Participants: \(hostedEventManager.participants.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Category Selection
    private var categorySelectionSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Message Categories")
                    .font(.headline)
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(MessageCategory.allCases, id: \.self) { category in
                        Button {
                            selectedMessageCategory = category
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: category.icon)
                                    .font(.caption)
                                
                                Text(category.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedMessageCategory == category ? category.color.opacity(0.2) : .gray.opacity(0.1))
                            .foregroundColor(selectedMessageCategory == category ? category.color : .primary)
                            .cornerRadius(20)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Predefined Messages
    private var predefinedMessagesSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: selectedMessageCategory.icon)
                    .foregroundColor(selectedMessageCategory.color)
                
                Text("\(selectedMessageCategory.rawValue) Messages")
                    .font(.headline)
                
                Spacer()
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 12) {
                ForEach(predefinedMessages[selectedMessageCategory] ?? [], id: \.self) { message in
                    Button {
                        sendQuickMessage(message)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message)
                                .font(.body)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            HStack {
                                Spacer()
                                
                                Image(systemName: "paperplane.fill")
                                    .font(.caption)
                                    .foregroundColor(selectedMessageCategory.color)
                            }
                        }
                        .padding()
                        .background(.gray.opacity(0.05))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedMessageCategory.color.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    // MARK: - Custom Message Section
    private var customMessageSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("✏️ Custom Message")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 12) {
                TextField("Type your message here...", text: $customMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                
                HStack {
                    Text("\(customMessage.count)/200")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Send Custom Message") {
                        sendQuickMessage(customMessage)
                        customMessage = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .background(.blue.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Voice Message Section
    private var voiceMessageSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("🎤 Voice Message")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 12) {
                if !isRecording {
                    Button {
                        startRecording()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mic.circle.fill")
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Record Voice Message")
                                    .font(.headline)
                                
                                Text("Hold to record, release to send")
                                    .font(.caption)
                                    .opacity(0.8)
                            }
                            
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(.green)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    VStack(spacing: 8) {
                        HStack {
                            Circle()
                                .fill(.red)
                                .frame(width: 12, height: 12)
                                .scaleEffect(isRecording ? 1.5 : 1.0)
                                .animation(.easeInOut(duration: 0.5).repeatForever(), value: isRecording)
                            
                            Text("Recording...")
                                .font(.headline)
                                .foregroundColor(.red)
                            
                            Spacer()
                            
                            Text(String(format: "%.1fs", recordingTime))
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        
                        HStack(spacing: 16) {
                            Button("Cancel") {
                                stopRecording(send: false)
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                            
                            Button("Send") {
                                stopRecording(send: true)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                    .background(.red.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    // MARK: - Broadcast History
    private var broadcastHistorySection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("📜 Recent Messages")
                    .font(.headline)
                Spacer()
                
                Button("Clear History") {
                    // Clear message history
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                ForEach(recentMessages, id: \.self) { message in
                    HStack {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Button {
                            sendQuickMessage(message)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Computed Properties
    
    private var recentMessages: [String] {
        // This would come from a stored history
        return [
            "⏰ 30 seconds remaining!",
            "📢 Welcome everyone! Let's get started.",
            "🎉 Great job on that round!"
        ]
    }
    
    // MARK: - Actions
    
    private func sendQuickMessage(_ message: String) {
        print("📢 [Host] Sending quick message: \(message)")
        
        // Send via SharePlay/notifications
        Task {
            await hostedEventManager.triggerNotification(message)
        }
        
        // Also trigger audio broadcast
        hostAudioManager.broadcastToAllRooms()
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func startRecording() {
        isRecording = true
        recordingTime = 0
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingTime += 0.1
            
            // Auto-stop at 30 seconds
            if recordingTime >= 30.0 {
                stopRecording(send: true)
            }
        }
        
        // Start actual audio recording here
        print("🎤 [Host] Started recording voice message")
    }
    
    private func stopRecording(send: Bool) {
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        if send {
            print("📤 [Host] Sending voice message (\(String(format: "%.1f", recordingTime))s)")
            sendQuickMessage("🎤 Voice message from host (\(String(format: "%.1f", recordingTime))s)")
        } else {
            print("❌ [Host] Cancelled voice message")
        }
        
        recordingTime = 0
    }
}
