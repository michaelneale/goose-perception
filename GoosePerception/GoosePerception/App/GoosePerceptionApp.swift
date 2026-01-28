import SwiftUI

@main
struct GoosePerceptionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Handle test modes - these run and exit, so we don't need the full app
        if CommandLine.arguments.contains("--test-harness") {
            Task { @MainActor in
                await TestHarness.run()
            }
            // Note: TestHarness.run() calls exit() when done
        }
        // --self-test is handled in AppDelegate.applicationDidFinishLaunching
    }
    
    var body: some Scene {
        // Menu bar app - no main window
        Settings {
            AppSettingsView()
        }
    }
}

/// Minimal settings - just app preferences, not service controls
/// Service controls are in the Dashboard
struct AppSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("retentionDays") private var retentionDays = 30.0
    
    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
            
            Section("Data Retention") {
                Slider(value: $retentionDays, in: 7...90, step: 7) {
                    Text("Keep data for \(Int(retentionDays)) days")
                }
                Text("Older data will be automatically deleted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Data") {
                Button("Clear All Data", role: .destructive) {
                    // TODO: Implement data clearing
                }
                Text("This will delete all captures, transcriptions, and insights")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                HStack {
                    Spacer()
                    Text("Service controls are in the Dashboard")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}
