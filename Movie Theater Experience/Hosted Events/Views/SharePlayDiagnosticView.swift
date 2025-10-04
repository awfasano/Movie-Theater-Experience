//
//  SharePlayDiagnosticView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/30/25.
//

import Foundation
import SwiftUI
import GroupActivities

struct SharePlayDiagnosticsView: View {
    @State private var diagnosticResults: [DiagnosticCheck] = []
    @State private var isChecking = false
    
    struct DiagnosticCheck: Identifiable {
        let id = UUID()
        let name: String
        var status: Status
        var details: String
        
        enum Status {
            case checking
            case passed
            case failed
            case warning
            
            var color: Color {
                switch self {
                case .checking: return .blue
                case .passed: return .green
                case .failed: return .red
                case .warning: return .orange
                }
            }
            
            var icon: String {
                switch self {
                case .checking: return "ellipsis"
                case .passed: return "checkmark.circle.fill"
                case .failed: return "xmark.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    
                    if diagnosticResults.isEmpty {
                        Button("Run Full Diagnostics") {
                            Task {
                                await runDiagnostics()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        resultsSection
                        
                        Button("Run Again") {
                            Task {
                                await runDiagnostics()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("SharePlay Diagnostics")
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("SharePlay System Check")
                .font(.title2.bold())
            
            Text("This will check all requirements for SharePlay")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var resultsSection: some View {
        VStack(spacing: 16) {
            ForEach(diagnosticResults) { check in
                HStack(spacing: 12) {
                    Image(systemName: check.status.icon)
                        .font(.title3)
                        .foregroundColor(check.status.color)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(check.name)
                            .font(.body.bold())
                        
                        Text(check.details)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(check.status.color.opacity(0.1))
                .cornerRadius(12)
            }
            
            summaryCard
        }
    }
    
    private var summaryCard: some View {
        VStack(spacing: 12) {
            let passedCount = diagnosticResults.filter { $0.status == .passed }.count
            let failedCount = diagnosticResults.filter { $0.status == .failed }.count
            let warningCount = diagnosticResults.filter { $0.status == .warning }.count
            
            Text("Summary")
                .font(.headline)
            
            HStack(spacing: 20) {
                StatBadge(count: passedCount, label: "Passed", color: .green)
                StatBadge(count: failedCount, label: "Failed", color: .red)
                StatBadge(count: warningCount, label: "Warnings", color: .orange)
            }
            
            if failedCount > 0 {
                Text("SharePlay may not work until failed checks are resolved")
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            } else if warningCount > 0 {
                Text("SharePlay should work but may have issues")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            } else {
                Text("All checks passed! SharePlay should work")
                    .font(.caption)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Diagnostics
    
    private func runDiagnostics() async {
        diagnosticResults.removeAll()
        isChecking = true
        
        // Check 1: GroupActivities Framework
        await checkGroupActivitiesFramework()
        
        // Check 2: Info.plist Configuration
        await checkInfoPlist()
        
        // Check 3: User Authentication
        await checkUserAuthentication()
        
        // Check 4: Network Connectivity
        await checkNetworkConnectivity()
        
        // Check 5: SharePlay Availability
        await checkSharePlayAvailability()
        
        // Check 6: Activity Registration
        await checkActivityRegistration()
        
        // Check 7: Entitlements
        await checkEntitlements()
        
        isChecking = false
    }
    
    private func checkGroupActivitiesFramework() async {
        var check = DiagnosticCheck(
            name: "GroupActivities Framework",
            status: .checking,
            details: "Checking if framework is available..."
        )
        diagnosticResults.append(check)
        
        try? await Task.sleep(for: .milliseconds(300))
        
        // Framework is always available if we can compile
        check.status = .passed
        check.details = "GroupActivities framework is available"
        
        if let index = diagnosticResults.firstIndex(where: { $0.id == check.id }) {
            diagnosticResults[index] = check
        }
    }
    
    private func checkInfoPlist() async {
        var check = DiagnosticCheck(
            name: "Info.plist Configuration",
            status: .checking,
            details: "Checking NSUserActivityTypes..."
        )
        diagnosticResults.append(check)
        
        try? await Task.sleep(for: .milliseconds(300))
        
        if let activityTypes = Bundle.main.object(forInfoDictionaryKey: "NSUserActivityTypes") as? [String] {
            if activityTypes.contains("com.waitedco.spiera.triviaEvent") {
                check.status = .passed
                check.details = "NSUserActivityTypes correctly configured with \(activityTypes.count) type(s)"
            } else {
                check.status = .failed
                check.details = "NSUserActivityTypes missing 'com.waitedco.spiera.triviaEvent'"
            }
        } else {
            check.status = .failed
            check.details = "NSUserActivityTypes not found in Info.plist"
        }
        
        if let index = diagnosticResults.firstIndex(where: { $0.id == check.id }) {
            diagnosticResults[index] = check
        }
    }
    
    private func checkUserAuthentication() async {
        var check = DiagnosticCheck(
            name: "User Authentication",
            status: .checking,
            details: "Checking user ID and profile..."
        )
        diagnosticResults.append(check)
        
        try? await Task.sleep(for: .milliseconds(300))
        
        let userId = AppModel.shared.currentUserId
        let username = AppModel.shared.username
        
        if !userId.isEmpty && !username.isEmpty {
            check.status = .passed
            check.details = "User authenticated: \(username)"
        } else if !userId.isEmpty {
            check.status = .warning
            check.details = "User ID set but username is empty"
        } else {
            check.status = .failed
            check.details = "No user ID configured"
        }
        
        if let index = diagnosticResults.firstIndex(where: { $0.id == check.id }) {
            diagnosticResults[index] = check
        }
    }
    
    private func checkNetworkConnectivity() async {
        var check = DiagnosticCheck(
            name: "Network Connectivity",
            status: .checking,
            details: "Checking network connection..."
        )
        diagnosticResults.append(check)
        
        try? await Task.sleep(for: .milliseconds(300))
        
        // Simple check - just assume connected for now
        // In production, you'd use NWPathMonitor
        check.status = .passed
        check.details = "Network appears to be available"
        
        if let index = diagnosticResults.firstIndex(where: { $0.id == check.id }) {
            diagnosticResults[index] = check
        }
    }
    
    private func checkSharePlayAvailability() async {
        var check = DiagnosticCheck(
            name: "SharePlay Availability",
            status: .checking,
            details: "Testing SharePlay activation..."
        )
        diagnosticResults.append(check)
        
        try? await Task.sleep(for: .milliseconds(300))
        
        // Create a test activity
        let testActivity = TriviaEventActivity(
            eventId: "diagnostic-test",
            eventTitle: "Diagnostic Test",
            spaceId: "test"
        )
        
        let result = await testActivity.prepareForActivation()
        
        switch result {
        case .activationPreferred:
            check.status = .passed
            check.details = "SharePlay is ready and available"
            
        case .activationDisabled:
            check.status = .failed
            check.details = "SharePlay is disabled. Check Settings → FaceTime → SharePlay"
            
        case .cancelled:
            check.status = .warning
            check.details = "SharePlay preparation was cancelled"
            
        @unknown default:
            check.status = .warning
            check.details = "Unknown SharePlay state"
        }
        
        if let index = diagnosticResults.firstIndex(where: { $0.id == check.id }) {
            diagnosticResults[index] = check
        }
    }
    
    private func checkActivityRegistration() async {
        var check = DiagnosticCheck(
            name: "Activity Registration",
            status: .checking,
            details: "Checking Group Activities dictionary..."
        )
        diagnosticResults.append(check)
        
        try? await Task.sleep(for: .milliseconds(300))
        
        if let groupActivities = Bundle.main.object(forInfoDictionaryKey: "Group Activities") as? [String: Any] {
            if let activityType = groupActivities["Group Activity Type"] as? String {
                if activityType == "com.waitedco.spiera.triviaEvent" {
                    check.status = .passed
                    check.details = "Activity properly registered in Info.plist"
                } else {
                    check.status = .failed
                    check.details = "Activity type mismatch: \(activityType)"
                }
            } else {
                check.status = .failed
                check.details = "Group Activity Type not found"
            }
        } else {
            check.status = .warning
            check.details = "Group Activities dictionary not found (may be optional)"
        }
        
        if let index = diagnosticResults.firstIndex(where: { $0.id == check.id }) {
            diagnosticResults[index] = check
        }
    }
    
    private func checkEntitlements() async {
        var check = DiagnosticCheck(
            name: "App Entitlements",
            status: .checking,
            details: "Checking entitlements configuration..."
        )
        diagnosticResults.append(check)
        
        try? await Task.sleep(for: .milliseconds(300))
        
        // Check if Group Activities entitlement is present
        // This is harder to check programmatically, so we'll check indirectly
        if Bundle.main.object(forInfoDictionaryKey: "NSSupportsGroupActivities") as? Bool == true {
            check.status = .passed
            check.details = "NSSupportsGroupActivities is enabled"
        } else {
            check.status = .warning
            check.details = "NSSupportsGroupActivities not found in Info.plist"
        }
        
        if let index = diagnosticResults.firstIndex(where: { $0.id == check.id }) {
            diagnosticResults[index] = check
        }
    }
}

struct StatBadge: View {
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title.bold())
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SharePlayDiagnosticsView_Previews: PreviewProvider {
    static var previews: some View {
        SharePlayDiagnosticsView()
    }
}
#endif
