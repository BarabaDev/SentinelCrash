import SwiftUI

struct ContentView: View {
    @EnvironmentObject var crashMonitor: CrashMonitorService
    @EnvironmentObject var settings: SettingsManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("tab.dashboard".localized, systemImage: "shield.fill")
                }
                .tag(0)
            
            CrashListView()
                .tabItem {
                    Label("tab.crashes".localized, systemImage: "exclamationmark.triangle.fill")
                }
                .tag(1)
            
            ToolsHubView()
                .tabItem {
                    Label("tab.tools".localized, systemImage: "wrench.and.screwdriver.fill")
                }
                .tag(2)
            
            AnalyticsView()
                .tabItem {
                    Label("tab.analytics".localized, systemImage: "chart.bar.xaxis")
                }
                .tag(3)
            
            SettingsView()
                .tabItem {
                    Label("tab.settings".localized, systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .accentColor(.cyan)
        .preferredColorScheme(.dark)
    }
}
