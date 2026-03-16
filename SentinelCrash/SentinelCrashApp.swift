import SwiftUI

@main
struct SentinelCrashApp: App {
    @StateObject private var crashMonitor = CrashMonitorService()
    @StateObject private var settingsManager = SettingsManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(crashMonitor)
                .environmentObject(settingsManager)
                .preferredColorScheme(.dark)
                .onAppear {
                    crashMonitor.configure(with: settingsManager)
                    crashMonitor.startMonitoring()
                }
        }
    }
}
